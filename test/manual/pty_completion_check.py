#!/usr/bin/env python3
"""Manual verification for the REPL's native Tab-completion (ADR-0053).

CI has no controlling terminal, so the TTY line-editing path (`user_drv`
line-editing group + `expand_fun`) cannot run under ExUnit. This harness drives
a real `mix rian.repl` inside a pseudo-terminal, defines a uniquely-named
function, types a prefix, presses Tab, and checks the name is completed — then
exits with `\\quit` and asserts a clean shutdown (terminal restored).

The completion *logic* is unit-tested separately:
  * `Rian.Repl.complete/2`                      (test/rian/repl_test.exs)
  * `Mix.Tasks.Rian.Repl.completion_for/2`      (test/mix/tasks/rian_repl_test.exs)

Run from the repo root:
    python3 test/manual/pty_completion_check.py
Exit code 0 means completion fired and the REPL quit cleanly.
"""
import os
import pty
import select
import signal
import sys
import time

REPL_DIR = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))


def main():
    pid, fd = pty.fork()
    if pid == 0:  # child becomes the REPL
        os.chdir(REPL_DIR)
        env = dict(os.environ, MIX_ENV="test", TERM="xterm-256color")
        os.execvpe("mix", ["mix", "rian.repl"], env)
        os._exit(127)

    buf = bytearray()

    def pump(seconds):
        end = time.time() + seconds
        while time.time() < end:
            r, _, _ = select.select([fd], [], [], 0.2)
            if r:
                try:
                    data = os.read(fd, 4096)
                except OSError:
                    return
                if not data:
                    return
                buf.extend(data)

    def send(s):
        os.write(fd, s.encode())
        time.sleep(0.4)

    pump(60)  # compile + banner + first prompt
    send("def zebra(n Int64) Int64\n")
    send("def zebra(n) := n\n")
    send("\n")  # blank line submits the definition
    pump(3)
    mark = len(buf)
    send("zeb\t")  # prefix + Tab → expect completion to "zebra"
    pump(3)
    completed = b"zebra" in bytes(buf[mark:])

    send("\x15")  # Ctrl-U clears the line buffer
    send("\\quit\n")
    exited, status = False, None
    for _ in range(40):
        pump(0.2)
        wpid, st = os.waitpid(pid, os.WNOHANG)
        if wpid == pid:
            exited, status = True, st
            break
    if not exited:
        os.kill(pid, signal.SIGKILL)
        os.waitpid(pid, 0)

    print("Tab-completion fired:", completed)
    print("clean exit:", exited, "status:", status)
    sys.exit(0 if (completed and exited and status == 0) else 1)


if __name__ == "__main__":
    main()

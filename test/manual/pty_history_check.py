#!/usr/bin/env python3
"""Manual verification that REPL history persists across sessions (ADR-0053).

CI has no controlling terminal, so the line-editing history path cannot run
under ExUnit. This harness runs two `mix rian.repl` sessions in a pseudo-terminal
sharing one history file (RIAN_HISTORY): the first enters a marker line, the
second presses Up-arrow and must recall it.

The `Rian.Repl.History` file format/dedup logic is unit-tested separately in
test/rian/repl/history_test.exs.

Run from the repo root:
    python3 test/manual/pty_history_check.py
Exit code 0 means the marker was persisted and recalled in a fresh session.
"""
import os
import pty
import select
import signal
import sys
import time

REPL_DIR = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
HIST = os.path.join("/tmp", "rian_history_check_%d" % os.getpid())


def run_session(keystrokes):
    pid, fd = pty.fork()
    if pid == 0:
        os.chdir(REPL_DIR)
        env = dict(os.environ, MIX_ENV="test", TERM="xterm-256color", RIAN_HISTORY=HIST)
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

    pump(90)  # compile + banner
    mark = len(buf)
    for k in keystrokes:
        send(k)
    pump(2)
    tail = bytes(buf[mark:])
    send("\x15")  # clear line
    send("\\quit\n")
    for _ in range(40):
        pump(0.2)
        if os.waitpid(pid, os.WNOHANG)[0] == pid:
            break
    else:
        os.kill(pid, signal.SIGKILL)
        os.waitpid(pid, 0)
    return tail


def main():
    if os.path.exists(HIST):
        os.remove(HIST)
    run_session(["marker7 := 7\n"])  # session 1 writes a marker
    persisted = os.path.exists(HIST) and "marker7" in open(HIST).read()
    recalled = b"marker7" in run_session(["\x1b[A"])  # session 2: Up-arrow recalls it
    if os.path.exists(HIST):
        os.remove(HIST)
    print("persisted:", persisted, "recalled:", recalled)
    sys.exit(0 if (persisted and recalled) else 1)


if __name__ == "__main__":
    main()

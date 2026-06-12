defmodule Mix.Tasks.Rian.Repl do
  @shortdoc "Start the Rian REPL (a compiling REPL, ADR-0053)"

  @moduledoc """
  An interactive Rian REPL — a **compiling** REPL (ADR-0053): every entry is
  parsed, type-checked, lowered to Erlang abstract forms, loaded, and run, so
  what evaluates at the prompt passed the full gate.

      mix rian.repl                 # interactive
      mix rian.repl --eval "EXPR"   # evaluate one entry and exit
      mix rian.repl --completions   # print the completion word list (for rlwrap)

  ## Line editing, history & completion

  On a real terminal the REPL upgrades the `-noshell` `user_drv` into an
  interactive line-editing group (via `:user_drv.start_shell/1`) and runs the
  session there, so it gets the native Erlang line editor — history, arrow-key
  recall — plus **Rian-aware Tab-completion**: an `expand_fun` backed by
  `Rian.Repl.complete/2` completes keywords, the `\\` meta-commands, and the
  session's own defined/bound names. The banner confirms when this is active.

  When stdin/stdout is not a TTY (a pipe, or an IO server without line editing)
  the REPL falls back to canonical-mode reads. For history and editing there,
  wrap it with [`rlwrap`](https://github.com/hanslub42/rlwrap):

      rlwrap mix rian.repl

  `rlwrap` can complete the fixed language vocabulary from the static word list
  this task prints (session names aren't known ahead of time in that mode):

      rlwrap -f <(mix rian.repl --completions) mix rian.repl

  ## Meta-commands

  Lines beginning with `\\` are surface commands, not Rian (the lexer never
  starts an expression with `\\`, so they can't collide with code): `\\help`,
  `\\env` (names defined/bound in the session), `\\type EXPR` (infer a type
  without evaluating), `\\reset` (fresh session), and `\\quit` (exit — the
  portable way out, since in line-editing mode `Ctrl-D` is forward-delete, not
  EOF).

  ## Entries

  An **expression** or `:=` binding evaluates on `Enter`. A **declaration**
  (`def`/`type`/…) or an open `do …` block accumulates until a **blank line**,
  so multi-clause functions and multi-line blocks can be entered. Each result
  prints as `value : Type`; a `:=` prints `name := value : Type`; a definition
  prints `defined name`. Unsupported constructs report a clear error rather
  than miscompiling — see `Rian.Repl` for the current `Rian.Beam` scope.

  ## Security: `--eval` is trusted-input only

  `--eval` runs whatever string it is given through the full compile pipeline
  and then `apply/3` on the bytecode — equivalent to `python -c` or `ruby -e`.
  Treat the argument as code, not data: never interpolate untrusted input into
  `mix rian.repl --eval "..."` from a shell script, CI step, or web handler.
  If you need to expose evaluation to untrusted input, wait for the
  connected-REPL sandbox/fuel story (ADR-0053 §2) and gate through that
  instead.
  """

  use Mix.Task

  alias Rian.Repl

  # The surface's declaration keywords (mirrors `Rian.Decl`): an entry starting
  # with one of these accumulates until a blank line, so all of a function's
  # clauses can be entered as one unit.
  @decl_keywords ~w(def type struct alias const mod)

  @impl Mix.Task
  def run(args) do
    {opts, argv, invalid} =
      OptionParser.parse(args, strict: [eval: :string, completions: :boolean])

    if invalid != [],
      do: Mix.raise("unknown option(s): #{inspect(Enum.map(invalid, &elem(&1, 0)))}")

    if argv != [], do: Mix.raise("usage: mix rian.repl [--eval \"EXPR\" | --completions]")

    cond do
      # A static word list for `rlwrap -f` — see the rlwrap note in the moduledoc.
      # No compile needed: the list is the language's fixed vocabulary.
      opts[:completions] -> dump_completions()
      # Ensure the project (and Rian.*) is compiled before we call into it.
      opts[:eval] -> with_compiled(fn -> eval_once(opts[:eval]) end)
      true -> with_compiled(&interactive/0)
    end
  end

  defp with_compiled(fun) do
    Mix.Task.run("compile")
    fun.()
  end

  defp eval_once(src) do
    {result, _session} = Repl.eval(Repl.new(), src)
    print(Repl.render(result))
  end

  # On a real terminal, run inside a native line-editing group (history, arrow
  # recall, and Rian-aware tab-completion via `expand_fun`); otherwise read
  # through canonical mode, where `rlwrap mix rian.repl` supplies history.
  defp interactive do
    if tty?() and start_line_editing_reader() == :ok do
      # The reader runs the session in its own process and signals us at EOF; the
      # graceful `System.stop/0` then restores the terminal as the VM shuts down.
      receive do
        :rian_repl_eof -> System.stop()
      end

      Process.sleep(:infinity)
    else
      IO.puts(banner(false))
      loop(Repl.new())
    end
  end

  defp tty?() do
    :prim_tty.isatty(:stdin) == true and :prim_tty.isatty(:stdout) == true
  rescue
    _ -> false
  catch
    _, _ -> false
  end

  # Upgrade the `-noshell` user_drv into an interactive line-editing group whose
  # "shell" is our reader. `start_shell/1` runs the MFA, which must spawn the
  # reader process and return its pid (the spawned process inherits the editing
  # group as its group leader, so `IO.gets` there gets edlin + completion).
  defp start_line_editing_reader do
    ensure_completion_table()
    parent = self()

    case :user_drv.start_shell(%{initial_shell: {__MODULE__, :reader_spawn, [parent]}}) do
      :ok -> :ok
      _ -> :error
    end
  rescue
    _ -> :error
  catch
    _, _ -> :error
  end

  @doc false
  def reader_spawn(parent), do: spawn(fn -> reader_run(parent) end)

  defp reader_run(parent) do
    :io.setopts([{:expand_fun, &__MODULE__.expand_fun/1}])
    IO.puts(banner(true))
    loop(Repl.new())
    send(parent, :rian_repl_eof)
    Process.sleep(:infinity)
  end

  @doc """
  The read → eval → print loop over the standard IO device. Public so it can be
  driven from a captured device in tests; `run/1` is the normal entry point.
  """
  @spec loop(Repl.t()) :: :ok
  def loop(session) do
    track_session(session)

    case read_entry() do
      :eof ->
        IO.write("\n")
        :ok

      {:entry, text} ->
        case handle_entry(text, session) do
          :halt ->
            IO.write("\n")
            :ok

          next ->
            loop(next)
        end
    end
  end

  # Dispatch one entry: a `\\`-prefixed meta-command, or Rian to evaluate.
  # Returns the next session (a command may reset it; eval advances it).
  defp handle_entry(text, session) do
    case command(text) do
      :none ->
        {result, session} = Repl.eval(session, text)
        print(Repl.render(result))
        session

      {:help, _} ->
        print(help_text())
        session

      {:env, _} ->
        print(render_env(Repl.info(session)))
        session

      {:type, ""} ->
        print("usage: \\type EXPR")
        session

      {:type, expr} ->
        print(render_type(Repl.type_of(session, expr), expr))
        session

      {:reset, _} ->
        print("session reset")
        Repl.new()

      {:quit, _} ->
        :halt

      {:unknown, cmd} ->
        print("unknown command: #{cmd} (try \\help)")
        session
    end
  end

  # A surface meta-command is a line whose first token starts with `\\` — a
  # prefix the Rian lexer can never begin an expression with (atoms are `:name`,
  # not `\\name`), so commands never collide with code.
  defp command(text) do
    case String.split(String.trim(text), ~r/\s+/, parts: 2) do
      ["\\help"] -> {:help, ""}
      ["\\h"] -> {:help, ""}
      ["\\?"] -> {:help, ""}
      ["\\env"] -> {:env, ""}
      ["\\reset"] -> {:reset, ""}
      ["\\quit"] -> {:quit, ""}
      ["\\q"] -> {:quit, ""}
      ["\\type", expr] -> {:type, expr}
      ["\\type"] -> {:type, ""}
      ["\\" <> _ = cmd | _] -> {:unknown, cmd}
      _ -> :none
    end
  end

  # Accumulate input lines into one entry. An expression/`:=` line submits as
  # soon as it is complete (balanced `do`/`end`); a declaration or an open block
  # accumulates until a blank line. The prompt is passed to `IO.gets/1` (not
  # written separately) so a line editor — native or `rlwrap` — owns the line.
  defp read_entry(buffer \\ "") do
    prompt = if buffer == "", do: prompt(), else: continuation_prompt()

    case IO.gets(prompt) do
      :eof -> if blank?(buffer), do: :eof, else: {:entry, buffer}
      {:error, _reason} -> :eof
      # A captured StringIO yields a binary; the line-editing group yields a
      # charlist — normalize both to a string.
      data -> accumulate(buffer, IO.chardata_to_string(data))
    end
  end

  defp accumulate(buffer, line) do
    cond do
      blank?(line) and blank?(buffer) -> read_entry("")
      blank?(line) -> {:entry, buffer}
      true -> continue(buffer <> line)
    end
  end

  defp continue(buffer) do
    if submit_on_enter?(buffer), do: {:entry, buffer}, else: read_entry(buffer)
  end

  # An entry submits on Enter when it is neither a (continuable) declaration nor
  # an unterminated `do …` block.
  defp submit_on_enter?(buffer) do
    trimmed = String.trim(buffer)
    not declaration?(trimmed) and balanced?(trimmed)
  end

  defp declaration?(input),
    do: Regex.match?(~r/\A(#{Enum.join(@decl_keywords, "|")})\b/, input)

  defp balanced?(input),
    do: count(input, ~r/\bdo\b/) <= count(input, ~r/\bend\b/)

  defp count(input, regex), do: length(Regex.scan(regex, input))

  defp blank?(string), do: String.trim(string) == ""

  defp print(""), do: :ok
  defp print(text), do: IO.puts(text)

  defp prompt, do: "rian> "
  defp continuation_prompt, do: "...> "

  defp help_text do
    String.trim_trailing("""
    Commands (\\-prefixed):
      \\help, \\h, \\?    show this help
      \\env             names defined and bound in the session
      \\type EXPR       infer EXPR's type without evaluating it
      \\reset           start a fresh session
      \\quit, \\q        exit the REPL
    Everything else is Rian: expressions evaluate on Enter; finish a definition with a blank line.
    """)
  end

  defp render_env(%{defined: [], bound: []}), do: "(empty session)"

  defp render_env(%{defined: defined, bound: bound}) do
    [names_line("defined", defined), names_line("bound", bound)]
    |> Enum.reject(&is_nil/1)
    |> Enum.join("\n")
  end

  defp names_line(_label, []), do: nil
  defp names_line(label, names), do: "#{label}: #{Enum.join(names, ", ")}"

  defp render_type(nil, expr), do: "#{String.trim(expr)} : ?  (type not inferred)"
  defp render_type(type, expr), do: "#{String.trim(expr)} : #{type}"

  # One candidate per line for `rlwrap -f` static completion. The session's own
  # names aren't known ahead of time, so this is the fixed language vocabulary
  # (`Rian.Repl.vocabulary/0`) — the same source `complete/2` extends per session.
  defp dump_completions do
    Repl.vocabulary()
    |> Enum.uniq()
    |> Enum.sort()
    |> Enum.each(&IO.puts/1)
  end

  defp banner(editing?) do
    edit_hint =
      if editing?,
        do: "Line editing, history, and Tab-completion are on.",
        else: "For history/editing, run `rlwrap mix rian.repl`."

    "Rian REPL — compiling REPL (ADR-0053). " <>
      "Expressions evaluate on Enter; finish a definition with a blank line. " <>
      "\\help for commands; \\quit to exit. " <> edit_hint
  end

  # ── tab-completion (expand_fun) ──────────────────────────────────────────
  #
  # The line editor invokes `expand_fun/1` in the *group* process, not the loop
  # process, so the live session is shared through a public ETS table the loop
  # keeps current via `track_session/1`.

  @completion_table :rian_repl_completion

  defp ensure_completion_table do
    if :ets.whereis(@completion_table) == :undefined do
      :ets.new(@completion_table, [:named_table, :public, :set])
    end

    :ok
  end

  defp track_session(session) do
    if :ets.whereis(@completion_table) != :undefined do
      :ets.insert(@completion_table, {:session, session})
    end

    session
  end

  defp tracked_session do
    case :ets.whereis(@completion_table) != :undefined and
           :ets.lookup(@completion_table, :session) do
      [{:session, session}] -> session
      _ -> Repl.new()
    end
  end

  @doc false
  @spec expand_fun(charlist()) :: {:yes | :no, charlist(), [{charlist(), list()}]}
  def expand_fun(before_reversed), do: completion_for(before_reversed, tracked_session())

  @doc false
  @spec completion_for(charlist(), Repl.t()) :: {:yes | :no, charlist(), [{charlist(), list()}]}
  def completion_for(before_reversed, session) do
    text = before_reversed |> :lists.reverse() |> List.to_string()
    {candidates, completion} = Repl.complete(text, session)
    matches = Enum.map(candidates, &{String.to_charlist(&1), []})

    cond do
      candidates == [] -> {:no, ~c"", []}
      completion == "" -> {:no, ~c"", matches}
      true -> {:yes, String.to_charlist(completion), matches}
    end
  end
end

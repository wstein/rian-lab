defmodule Mix.Tasks.Rian.Repl do
  @shortdoc "Start the Rian REPL (a compiling REPL, ADR-0053)"

  @moduledoc """
  An interactive Rian REPL — a **compiling** REPL (ADR-0053): every entry is
  parsed, type-checked, lowered to Erlang abstract forms, loaded, and run, so
  what evaluates at the prompt passed the full gate.

      mix rian.repl                 # interactive
      mix rian.repl --eval "EXPR"   # evaluate one entry and exit
      mix rian.repl --completions   # print the completion word list (for rlwrap)

  ## Line editing & history

  `mix` launches the VM with `-noshell`, so the native Erlang line editor
  (history, arrow-key recall) is not available — `mix rian.repl` reads through
  the terminal's canonical mode (basic backspace only). For full readline
  editing, history, and reverse-search, wrap the REPL with
  [`rlwrap`](https://github.com/hanslub42/rlwrap):

      rlwrap mix rian.repl

  Tab-completion of the language vocabulary works by feeding `rlwrap` the static
  word list this task can print:

      rlwrap -f <(mix rian.repl --completions) mix rian.repl

  If the REPL is ever driven from an IO server that *does* support line editing,
  it enables history automatically and the banner says so.

  ## Meta-commands

  Lines beginning with `\\` are surface commands, not Rian (the lexer never
  starts an expression with `\\`, so they can't collide with code): `\\help`,
  `\\env` (names defined/bound in the session), `\\type EXPR` (infer a type
  without evaluating), and `\\reset` (fresh session).

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

  defp interactive do
    editing? = enable_line_editing()
    IO.puts(banner(editing?))
    loop(Repl.new())
  end

  # Try to turn on the native line editor + history. Under a plain `mix` task the
  # VM runs `-noshell` (no `user_drv`), so this returns `{:error, :enotsup}` and we
  # fall back to canonical-mode input — `rlwrap mix rian.repl` adds history there.
  defp enable_line_editing do
    :io.setopts(:standard_io, [{:line_editing, true}, {:line_history, true}]) == :ok
  rescue
    _ -> false
  catch
    _, _ -> false
  end

  @doc """
  The read → eval → print loop over the standard IO device. Public so it can be
  driven from a captured device in tests; `run/1` is the normal entry point.
  """
  @spec loop(Repl.t()) :: :ok
  def loop(session) do
    case read_entry() do
      :eof ->
        IO.write("\n")
        :ok

      {:entry, text} ->
        loop(handle_entry(text, session))
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
      line when is_binary(line) -> accumulate(buffer, line)
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
        do: "Line editing + history are on.",
        else: "For history/editing, run `rlwrap mix rian.repl`."

    "Rian REPL — compiling REPL (ADR-0053). " <>
      "Expressions evaluate on Enter; finish a definition with a blank line. " <>
      "\\help for commands; Ctrl-D to exit. " <> edit_hint
  end
end

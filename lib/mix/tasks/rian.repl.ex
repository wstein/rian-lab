defmodule Mix.Tasks.Rian.Repl do
  @shortdoc "Start the Rian REPL (a compiling REPL, ADR-0053)"

  @moduledoc """
  An interactive Rian REPL — a **compiling** REPL (ADR-0053): every entry is
  parsed, type-checked, lowered to Erlang abstract forms, loaded, and run, so
  what evaluates at the prompt passed the full gate.

      mix rian.repl                 # interactive
      mix rian.repl --eval "EXPR"   # evaluate one entry and exit

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
    {opts, argv, invalid} = OptionParser.parse(args, strict: [eval: :string])

    if invalid != [],
      do: Mix.raise("unknown option(s): #{inspect(Enum.map(invalid, &elem(&1, 0)))}")

    if argv != [], do: Mix.raise("usage: mix rian.repl [--eval \"EXPR\"]")

    # Ensure the project (and Rian.*) is compiled before we call into it.
    Mix.Task.run("compile")

    case opts[:eval] do
      nil -> interactive()
      src -> eval_once(src)
    end
  end

  defp eval_once(src) do
    {result, _session} = Repl.eval(Repl.new(), src)
    print(Repl.render(result))
  end

  defp interactive do
    IO.puts(banner())
    loop(Repl.new())
  end

  @doc """
  The read → eval → print loop over the standard IO device. Public so it can be
  driven from a captured device in tests; `run/1` is the normal entry point.
  """
  @spec loop(Repl.t()) :: :ok
  def loop(session) do
    IO.write(prompt())

    case read_entry() do
      :eof ->
        IO.write("\n")
        :ok

      {:entry, text} ->
        {result, session} = Repl.eval(session, text)
        print(Repl.render(result))
        loop(session)
    end
  end

  # Accumulate input lines into one entry. An expression/`:=` line submits as
  # soon as it is complete (balanced `do`/`end`); a declaration or an open block
  # accumulates until a blank line.
  defp read_entry(buffer \\ "") do
    case IO.read(:line) do
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
    if submit_on_enter?(buffer) do
      {:entry, buffer}
    else
      IO.write(continuation_prompt())
      read_entry(buffer)
    end
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

  defp banner do
    "Rian REPL — compiling REPL (ADR-0053). " <>
      "Expressions evaluate on Enter; finish a definition with a blank line. Ctrl-D to exit."
  end
end

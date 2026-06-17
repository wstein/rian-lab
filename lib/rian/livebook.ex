defmodule Rian.Livebook do
  use Rian.Ann

  @moduledoc """
  The Livebook surface for Rian (ADR-0053) — a thin driver over the shared
  `Rian.Repl` engine. It owns **no compiler logic**: the playground and Livebook
  meet only here, at the engine API, so neither can drift from the real compiler.

  A notebook keeps **one accumulating session** (a named `Agent`) for its runtime,
  so `def`/`type` declarations and top-level `:=` binds made in one Rian cell are
  visible to the next — the stateful exploration Livebook authors expect. Call
  `reset/0` from a plain Elixir cell to start a fresh session.

  `eval/1` is what a `Rian.Livebook.SmartCell` generates a call to: it splits the
  cell into `Rian.Repl.split_entries/1` entries, evaluates each against the shared
  session, and returns a `Kino` output rendering the results (`value : Type`, a
  `name := value` bind, `defined …`, or an `error:`). The pure `run/2` does the
  same against an explicit session and is what the tests drive.
  """

  alias Rian.Repl

  @server __MODULE__.Session

  @doc """
  Evaluate a cell's worth of Rian `source` against the notebook's shared session,
  returning a `Kino` output of the rendered results. Advances the shared session.
  """
  @spec eval(String.t()) :: term()
  def eval(source) when is_binary(source) do
    {lines, _session} =
      Agent.get_and_update(session_pid(), fn session ->
        {lines, session} = run(session, source)
        {{lines, session}, session}
      end)

    output(lines)
  end

  @doc """
  Evaluate `source` against an explicit `session` (no shared state, no IO).
  Returns `{rendered_lines, session'}` — one rendered string per non-empty entry,
  in order, and the advanced session. Pure; the engine seam the surfaces share.
  """
  @spec run(Repl.t(), String.t()) :: {[String.t()], Repl.t()}
  def run(session, source) do
    {rendered, session} =
      source
      |> Repl.split_entries()
      |> Enum.reduce({[], session}, fn entry, {acc, s} ->
        {result, s} = Repl.eval(s, entry)
        {[Repl.render(result) | acc], s}
      end)

    {rendered |> Enum.reverse() |> Enum.reject(&(&1 == "")), session}
  end

  @doc "Reset the notebook's shared session to a fresh, empty one."
  @rian "pub def reset() Symbol"
  @spec reset() :: :ok
  def reset do
    if pid = Process.whereis(@server), do: Agent.update(pid, fn _ -> Repl.new() end)
    :ok
  end

  # the shared session Agent, started on first use (a notebook may evaluate a Rian
  # cell before anything else touches the session). A named `Agent.start` is
  # idempotent: the first call starts it, every later call returns the running pid.
  defp session_pid do
    case Agent.start(fn -> Repl.new() end, name: @server) do
      {:ok, pid} -> pid
      {:error, {:already_started, pid}} -> pid
    end
  end

  # render the entries as one monospace block — a fenced code block reproduces the
  # `mix rian.repl` transcript look without HTML-escaping the values.
  defp output([]), do: Kino.Markdown.new("")
  defp output(lines), do: Kino.Markdown.new("```\n" <> Enum.join(lines, "\n") <> "\n```")
end

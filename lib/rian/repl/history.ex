defmodule Rian.Repl.History do
  use Rian.Ann

  @moduledoc """
  File-backed REPL history, persisted across sessions (ADR-0053).

  This is a custom provider for Erlang's shell-history hook: the interactive
  line-editing group ([`Mix.Tasks.Rian.Repl`](../../mix/tasks/rian.repl.ex))
  sets `kernel`'s `shell_history` env to this module, so `group_history` calls
  `load/0` once at startup to seed edlin's history (cross-session arrow-up
  recall) and `add/1` for each submitted line to persist it.

  History lives in `~/.rian_history` — a plain newline-delimited file, newest
  line last — capped at #{1000} lines so it can't grow without bound. The path
  is overridable for tests and power users via the `:rian_lab` app env
  `:history_file` or the `RIAN_HISTORY` environment variable.
  """

  @max_lines 1000

  @doc "The history file path (app env / `RIAN_HISTORY` / `~/.rian_history`)."
  @rian_sig "pub def path() String"
  @spec path() :: String.t()
  def path do
    case Application.get_env(:rian_lab, :history_file) do
      nil ->
        case System.get_env("RIAN_HISTORY") do
          nil -> Path.expand("~/.rian_history")
          env -> env
        end

      configured ->
        configured
    end
  end

  @doc """
  Load persisted history as a list of charlists, oldest first — the order
  `group_history` expects when seeding the line editor. Missing/unreadable files
  yield `[]` rather than failing the REPL.
  """
  @rian_sig "pub def load() Vec(_Unk)"
  @spec load() :: [charlist()]
  def load do
    case File.read(path()) do
      {:ok, contents} ->
        contents
        |> String.split("\n", trim: true)
        |> Enum.take(-@max_lines)
        |> Enum.map(&String.to_charlist/1)

      {:error, _reason} ->
        []
    end
  end

  @doc """
  Append one submitted line to the history file. Blank lines and an immediate
  repeat of the previous entry are dropped; the file is trimmed to its cap. Any
  IO error is swallowed so persistence can never take down a REPL session.
  """
  @rian_sig "pub def add(line String) Symbol"
  @spec add(iodata()) :: :ok
  @rian_host "best-effort host boundary: history file I/O must never crash the REPL"
  def add(line) do
    entry = line |> IO.chardata_to_string() |> String.trim_trailing("\n") |> String.trim()

    if entry != "" do
      kept =
        (load_strings() ++ [entry])
        |> dedup_consecutive()
        |> Enum.take(-@max_lines)

      File.write(path(), Enum.map(kept, &[&1, ?\n]))
    end

    :ok
  rescue
    _ -> :ok
  end

  @spec load_strings() :: [String.t()]
  defp load_strings, do: Enum.map(load(), &List.to_string/1)

  # Collapse runs of an identical line into one (consecutive dedup).
  defp dedup_consecutive([a, b | rest]) when a == b, do: dedup_consecutive([b | rest])
  defp dedup_consecutive([a | rest]), do: [a | dedup_consecutive(rest)]
  defp dedup_consecutive([]), do: []
end

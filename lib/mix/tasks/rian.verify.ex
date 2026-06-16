defmodule Mix.Tasks.Rian.Verify do
  @shortdoc "Per-function forms-equivalence: a Rian port vs its Elixir oracle"

  @moduledoc """
  The **verify gate** of the transpile loop: compile an Elixir oracle module and a
  candidate Rian port, then report per-function whether their normalized Erlang
  abstract forms match (`Rian.FormsEquiv`).

      mix rian.verify ELIXIR.ex RIAN.rian

  Each function is reported `✓ equiv`, `✗ diverges`, `· unported` (only in the
  oracle) or `? only in port`. Exit status is 0 iff every oracle function is
  `✓ equiv`, so this is usable as a CI gate or as the accept/reject step of a
  generate-and-verify porting loop: a proposer fills markers, this gate accepts
  only faithful candidates, and a candidate that does not even compile is a clean
  rejection (reported, exit 1) rather than a crash.

  Note: equiv-locking only applies to the portable subset — struct-reflection /
  stdlib-shaped code (Elixir structs are maps, Rian sums are tagged tuples) is not
  forms-equivalent and will report `✗ diverges`. See `Rian.FormsEquiv`.
  """

  use Mix.Task

  alias Rian.FormsEquiv

  @impl Mix.Task
  def run(args) do
    {ex_file, rian_file} =
      case args do
        [a, b | _] -> {a, b}
        _ -> Mix.raise("usage: mix rian.verify ELIXIR.ex RIAN.rian")
      end

    unless File.regular?(ex_file), do: Mix.raise("no such file: #{ex_file}")
    unless File.regular?(rian_file), do: Mix.raise("no such file: #{rian_file}")

    Code.put_compiler_option(:debug_info, true)
    ex_bin = compile_elixir(ex_file)

    case compile_rian(rian_file) do
      {:ok, rian_bin} ->
        ledger = FormsEquiv.verify(ex_bin, rian_bin)
        print_ledger(ledger)
        verdict(ledger)

      {:error, reason} ->
        IO.puts(:stderr, "NOT VERIFIED — Rian port does not compile yet:\n  #{reason}")
        exit({:shutdown, 1})
    end
  end

  defp compile_elixir(file) do
    {_mod, bin} = file |> File.read!() |> Code.compile_string(file) |> hd()
    bin
  end

  defp compile_rian(file) do
    {:ok, _mod, bin} = Rian.Beam.compile(File.read!(file), :"Elixir.RianVerifyPort")
    {:ok, bin}
  rescue
    e -> {:error, Exception.message(e)}
  end

  defp print_ledger(ledger) do
    IO.puts(:stderr, "function           status")

    for {{name, arity}, status} <- ledger do
      IO.puts(:stderr, "  #{String.pad_trailing("#{name}/#{arity}", 16)} #{label(status)}")
    end
  end

  defp label(:equiv), do: "✓ equiv"
  defp label(:diverges), do: "✗ diverges"
  defp label(:only_oracle), do: "· unported (only in Elixir)"
  defp label(:only_port), do: "? only in Rian port"

  defp verdict(ledger) do
    equiv = Enum.count(ledger, &(elem(&1, 1) == :equiv))

    if equiv == length(ledger) do
      IO.puts(:stderr, "\nVERIFIED ✓ — all #{equiv} function(s) equiv-lock")
    else
      IO.puts(:stderr, "\nNOT VERIFIED — #{equiv}/#{length(ledger)} equiv; resolve the ✗/· rows")
      exit({:shutdown, 1})
    end
  end
end

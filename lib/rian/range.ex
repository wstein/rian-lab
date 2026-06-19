defmodule Rian.Range do
  @moduledoc """
  Desugars **range construction** `Name.of(n)` (ADR-0036) into a portable
  in-bounds check, given the program's range table.

  A `range Digit := 0..9` gets a checked constructor `Digit.of(n) : Digit |
  RangeError`. Rather than teach every emitter a new construct, `Name.of(n)`
  rewrites — *before* lowering — to an ordinary `if`-Result the existing emitters
  already handle:

      Digit.of(n)  ~>  if 0 <= n and n <= 9 do {:ok, n} else {:error, RangeError} end

  So the value is `{:ok, n}` when in range and `{:error, RangeError}` otherwise —
  a `T | E` Result (ADR-0040). The rewrite is target-agnostic; an emitter only
  needs the range table threaded to its body-parse point.

  The argument is referenced more than once (two bound checks + the `:ok` branch);
  for the usual `Name.of(<var>)` this is a pure re-read. (A side-effecting argument
  would be evaluated more than once — bind it first if that matters.)
  """

  use Rian.Ann

  alias Rian.Core.{EAtom, EBin, ECall, EDot, EId, EIf, ENum, ETuple}

  @rian_sig "pub def table(ranges Vec(Range)) Dict(String, _Unk)"
  @doc "Build the `name -> %{lo, hi, base}` table from a list of `%Rian.IR.Range{}`."
  @spec table([map()]) :: map()
  def table(ranges),
    do: Map.new(ranges, fn r -> {r.name, %{lo: r.lo, hi: r.hi, base: r.base}} end)

  @rian_sig "pub def expand_of(node T, table Dict(String, _Unk)) T forall T"
  @doc "Rewrite every `Name.of(n)` (for a `Name` in `table`) in a core AST; identity when the table is empty."
  @spec expand_of(term(), map()) :: term()
  def expand_of(node, table) when map_size(table) == 0, do: node

  def expand_of(%ECall{fun: %EDot{head: %EId{name: n}, name: "of"}, args: [a]} = node, table) do
    case Map.get(table, n) do
      %{lo: lo, hi: hi} -> check(lo, hi, expand_of(a, table))
      _ -> walk(node, table)
    end
  end

  def expand_of(node, table) when is_struct(node), do: walk(node, table)
  def expand_of(list, table) when is_list(list), do: Enum.map(list, &expand_of(&1, table))

  def expand_of(tuple, table) when is_tuple(tuple),
    do: tuple |> Tuple.to_list() |> Enum.map(&expand_of(&1, table)) |> List.to_tuple()

  def expand_of(other, _table), do: other

  # rebuild a struct node with each child rewritten (non-AST fields pass through)
  defp walk(node, table),
    do:
      Enum.reduce(Map.from_struct(node), node, fn {k, v}, acc ->
        Map.put(acc, k, expand_of(v, table))
      end)

  # `if lo <= a and a <= hi do {:ok, a} else {:error, RangeError} end`
  defp check(lo, hi, a) do
    %EIf{
      cond: %EBin{
        op: "and",
        left: %EBin{op: "<=", left: lit(lo), right: a},
        right: %EBin{op: "<=", left: a, right: lit(hi)}
      },
      then: %ETuple{elems: [%EAtom{name: "ok"}, a]},
      else: %ETuple{elems: [%EAtom{name: "error"}, %EId{name: "RangeError"}]}
    }
  end

  defp lit(n), do: %ENum{text: Integer.to_string(n)}
end

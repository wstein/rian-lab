defmodule Rian.Prim do
  @moduledoc """
  Rewrites the `Prim.<name>(args)` surface namespace into the canonical
  compiler intrinsic `__prim_<name>(args)` before downstream passes see it.

  `Prim` is reserved as the **target-internal** namespace for the compiler
  primitives that each backend lowers natively (ADR-0047 §2 portable prelude):
  `Prim.str_chars`, `Prim.str_from_chars`, `Prim.str_concat`, `Prim.char_code`,
  `Prim.map_new`/`get`/`put`/`has`, `Prim.wrapping_add`/`saturating_add`/`checked_add`.

  Source code uses `Prim.X(args)`; the legacy `__prim_X(args)` form is still
  accepted (the rewrite produces it) but should no longer appear in tour or
  selfhost `.rian` source. The portable wrappers (`Str.chars/1`, `Char.code/1`,
  `Dict.get/2`, …) call through `Prim.*` instead of `__prim_*`.

  The pass runs at the `Rian.Pratt` AST boundary so every downstream walker
  (`Core.from_expr`, `Rian.Lower`'s borrow-insertion, the emitters) sees a
  single canonical call form.
  """

  @doc """
  Walk a tuple-form expression AST and rewrite `Prim.<name>(args)` calls into
  `__prim_<name>(args)`. Idempotent; non-`Prim` calls pass through unchanged.
  """
  def normalize({:call, {:dot, {:id, "Prim"}, name}, args}),
    do: {:call, {:id, "__prim_" <> name}, Enum.map(args, &normalize/1)}

  def normalize(node) when is_tuple(node) do
    node
    |> Tuple.to_list()
    |> Enum.map(&normalize/1)
    |> List.to_tuple()
  end

  def normalize(list) when is_list(list), do: Enum.map(list, &normalize/1)

  def normalize(other), do: other
end

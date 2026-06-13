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

  # The closed set of compiler intrinsics each backend lowers natively
  # (ADR-0047 §2). This is the surface registry — it must stay in sync with the
  # `__prim_*` clauses in `beam.ex` / `js.ex` / `lower.ex`. Because `Prim` is a
  # *reserved* namespace, only these names are rewritten; any other `Prim.x(…)`
  # is a hard error (a typo, or a collision with a user module named `Prim`),
  # never a silently-bogus `__prim_x` that fails cryptically downstream.
  @prims ~w(
    str_chars str_from_chars str_concat
    char_code
    map_new map_get map_put map_has
    wrapping_add saturating_add checked_add
  )

  @doc "The intrinsic names the reserved `Prim.*` surface exposes."
  def names, do: @prims

  @doc """
  Walk a tuple-form expression AST and rewrite `Prim.<name>(args)` calls into
  `__prim_<name>(args)`. Idempotent; non-`Prim` calls pass through unchanged; an
  unknown `Prim.<name>` raises (the namespace is reserved, ADR-0047 §2).
  """
  def normalize({:call, {:dot, {:id, "Prim"}, name}, args}) when name in @prims,
    do: {:call, {:id, "__prim_" <> name}, Enum.map(args, &normalize/1)}

  def normalize({:call, {:dot, {:id, "Prim"}, name}, _args}),
    do:
      raise(
        ArgumentError,
        "unknown primitive `Prim.#{name}` — `Prim` is the reserved intrinsic " <>
          "namespace (ADR-0047 §2); valid: #{Enum.join(@prims, ", ")}"
      )

  def normalize(node) when is_tuple(node) do
    node
    |> Tuple.to_list()
    |> Enum.map(&normalize/1)
    |> List.to_tuple()
  end

  def normalize(list) when is_list(list), do: Enum.map(list, &normalize/1)

  def normalize(other), do: other
end

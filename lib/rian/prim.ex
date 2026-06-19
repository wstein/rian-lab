defmodule Rian.Prim do
  use Rian.Ann

  @moduledoc """
  Rewrites the `Prim.<name>(args)` surface namespace into the canonical
  compiler intrinsic `__prim_<name>(args)` before downstream passes see it.

  `Prim` is reserved as the **target-internal** namespace for the compiler
  primitives that each backend lowers natively (ADR-0047 §2 portable prelude):
  `Prim.str_chars`, `Prim.str_from_chars`, `Prim.str_concat`, `Prim.str_concat_all`,
  `Prim.str_to_atom`, `Prim.char_code`, `Prim.map_new`/`get`/`put`/`has`,
  `Prim.wrapping_add`/`saturating_add`/`checked_add`, and `Prim.panic` — the
  diverging, **uncatchable** abort (ADR-0035/0040): `Prim.panic(msg) : T forall T`,
  lowering to `erlang:error`/`panic!`/`throw`/Kotlin `throw`. It has no Rian `catch`
  (so it is not hidden control flow — termination routes nowhere) and is portable
  to every target; use it for invariant violations / unreachable arms, never for an
  *expected* error (that is a `Result`).

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
    str_chars str_from_chars str_concat str_concat_all str_to_atom str_to_float
    char_code int_to_string int_to_float char_to_string
    map_new map_get map_put map_has
    wrapping_add saturating_add checked_add
    panic
  )

  # The explicit 64-bit-overflow ops (ADR-0035 §3 / ADR-0064 §2a): they carry the
  # fixed-width-64 two's-complement contract, so the JS emitter refuses them and
  # `Rian.Reach` pins a function that calls one off `:js`. Canonical here (in the
  # `__prim_*` form both consumers use) so the two never drift apart.
  @overflow_ops Enum.map(~w(wrapping_add saturating_add checked_add), &("__prim_" <> &1))

  @doc "The intrinsic names the reserved `Prim.*` surface exposes."
  @rian_sig "pub def names() Vec(String)"
  @spec names() :: [String.t()]
  def names, do: @prims

  @doc "The canonical `__prim_*` 64-bit-overflow ops (JS-unsupported; off `:js`)."
  @rian_sig "pub def overflow_ops() Vec(String)"
  @spec overflow_ops() :: [String.t()]
  def overflow_ops, do: @overflow_ops

  @rian_sig "pub def normalize(node _Unk) _Unk"
  @doc """
  Walk a tuple-form expression AST and rewrite `Prim.<name>(args)` calls into
  `__prim_<name>(args)`. Idempotent; non-`Prim` calls pass through unchanged; an
  unknown `Prim.<name>` raises (the namespace is reserved, ADR-0047 §2). A bare,
  1-arg `panic(msg)` is also rewritten to `__prim_panic(msg)` — the one primitive
  ergonomic enough to spell without the `Prim.` prefix (ADR-0035/0040).
  """
  @spec normalize(term()) :: term()
  def normalize({:call, {:dot, {:id, "Prim"}, name}, args}) when name in @prims,
    do: {:call, {:id, "__prim_" <> name}, Enum.map(args, &normalize/1)}

  def normalize({:call, {:dot, {:id, "Prim"}, name}, _args}),
    do:
      raise(
        ArgumentError,
        "unknown primitive `Prim.#{name}` — `Prim` is the reserved intrinsic " <>
          "namespace (ADR-0047 §2); valid: #{Enum.join(@prims, ", ")}"
      )

  # ergonomic bare `panic(msg)` ≡ `Prim.panic(msg)` (ADR-0035/0040): the diverging,
  # uncatchable abort. `panic` is a reserved builtin — a 1-arg `panic` call rewrites
  # to the intrinsic, so callers needn't write the `Prim.` prefix for the one
  # primitive that is genuinely surface-level (an invariant violation / unreachable
  # arm). Other arities pass through as an ordinary call.
  def normalize({:call, {:id, "panic"}, [arg]}),
    do: {:call, {:id, "__prim_panic"}, [normalize(arg)]}

  def normalize(node) when is_tuple(node) do
    node
    |> Tuple.to_list()
    |> Enum.map(&normalize/1)
    |> List.to_tuple()
  end

  def normalize(list) when is_list(list), do: Enum.map(list, &normalize/1)

  def normalize(other), do: other
end

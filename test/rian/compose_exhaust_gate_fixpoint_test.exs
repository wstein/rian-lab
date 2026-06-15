defmodule Rian.ComposeExhaustGateFixpointTest do
  # async: false — loads the verified ports + the driver into the VM.
  use ExUnit.Case, async: false

  alias Rian.Beam

  # SELF-CHECKING (ADR-0063 / ADR-0036) — the exhaustiveness gate, running INSIDE the
  # Rian compiler. The driver (selfhost_compose_real_sum.rian) builds the usefulness
  # env from a program's `type` declarations, converts each function's clause matrix,
  # and asks the verified `SelfhostExhaust.useful` (locked to `Rian.Exhaustiveness`
  # in exhaust_fixpoint_test) whether a wildcard row is useful — useful ⇒ an uncovered
  # case ⇒ NON-exhaustive. `non_exhaustive/1` returns "" if every checkable function
  # is exhaustive, else the first that is not.
  #
  # The gate decides the sum-type-dispatch subset (ctor/wild/var patterns, no guards);
  # functions with literals/lists/tuples/guards are conservatively SKIPPED (no false
  # refusal). This is the decision; `build` wiring (refusal) is locked separately.

  setup_all do
    {:ok, _} =
      Beam.load(File.read!("examples/rian/selfhost_lexer_v2.rian"), :"Elixir.SelfhostLexerV2")

    {:ok, _} = Beam.load(File.read!("examples/rian/selfhost_decl.rian"), :"Elixir.SelfhostDecl")
    {:ok, _} = Beam.load(File.read!("examples/rian/selfhost_beam.rian"), :"Elixir.SelfhostBeam")
    {:ok, _} = Beam.load(File.read!("examples/rian/selfhost_exhaust.rian"), :"Elixir.SelfhostExhaust")

    {:ok, drv} =
      Beam.load(File.read!("examples/rian/selfhost_compose_real_sum.rian"), :rian_exhaust_gate)

    {:ok, drv: drv}
  end

  # {source, the first non-exhaustive function ("" = all exhaustive)}.
  @cases [
    # nullary sum dispatch
    {"type C := A | B\ndef f(c C) Int53\ndef f(A) := 1\ndef f(B) := 2", ""},
    {"type C := A | B | D\ndef f(c C) Int53\ndef f(A) := 1\ndef f(B) := 2", "f"},
    {"type C := A | B | D\ndef f(c C) Int53\ndef f(A) := 1\ndef f(_) := 0", ""},
    # applied ctors (specialise by arity)
    {"type S := Cir(Int53) | Rec(Int53, Int53)\ndef ar(s S) Int53\ndef ar(Cir(r)) := r\ndef ar(Rec(w, h)) := w",
     ""},
    {"type S := Cir(Int53) | Rec(Int53, Int53) | Sq(Int53)\ndef ar(s S) Int53\ndef ar(Cir(r)) := r\ndef ar(Rec(w, h)) := w",
     "ar"},
    # multi-line type + parametric multi-arg variant (the selfhost_cap `Ty` shape):
    # a clause set covering all five variants is exhaustive.
    {"type Ty := TScalar(String)\n  | TString\n  | TNom(String)\n  | TVec(Ty)\n  | TGen(String, Vec(Ty), String)\ndef b(t Ty) Int53\ndef b(TScalar(_)) := 1\ndef b(TString) := 2\ndef b(TNom(_)) := 3\ndef b(TVec(_)) := 4\ndef b(TGen(_, _, _)) := 5",
     ""},
    # ... and missing one variant is caught
    {"type Ty := TScalar(String)\n  | TString\n  | TNom(String)\n  | TVec(Ty)\n  | TGen(String, Vec(Ty), String)\ndef b(t Ty) Int53\ndef b(TScalar(_)) := 1\ndef b(TString) := 2\ndef b(TNom(_)) := 3\ndef b(TVec(_)) := 4",
     "b"},
    # a function with a wildcard/literal patterns is SKIPPED (not refused)
    {"def g(n Int53) Int53\ndef g(0) := 1\ndef g(n) := n", ""}
  ]

  # the compiler's own sources — every checkable function must be exhaustive, or the
  # gate (once wired into build) would refuse to compile the compiler itself.
  @compiler_sources ~w(
    selfhost_lexer_v2 selfhost_decl selfhost_beam selfhost_core
    selfhost_cap selfhost_exhaust selfhost_compose_real_sum
  )

  describe "the exhaustiveness gate decides correctly, inside the Rian compiler" do
    test "non_exhaustive flags exactly the non-exhaustive sum-dispatch functions",
         %{drv: drv} do
      for {src, expected} <- @cases do
        assert drv.non_exhaustive(src) == expected,
               "gate diverged on #{inspect(src)} — got #{inspect(drv.non_exhaustive(src))}, expected #{inspect(expected)}"
      end
    end

    test "every compiler source passes the gate (so build can refuse without breaking itself)",
         %{drv: drv} do
      for f <- @compiler_sources do
        bad = drv.non_exhaustive(File.read!("examples/rian/#{f}.rian"))

        assert bad == "",
               "#{f}.rian has a non-exhaustive checkable function `#{bad}` — wiring the gate into build would break it"
      end
    end
  end
end

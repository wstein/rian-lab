defmodule Rian.SelfhostBuildTest do
  # async: false — loads real modules into the VM via :code.load_binary.
  use ExUnit.Case, async: false

  alias Rian.Beam

  # Rian-FIRST behavioural tests: drive the **self-hosted Rian compiler** (the
  # composed `build`: SelfhostLexerV2 → SelfhostDecl → lower → SelfhostBeam) with
  # real Rian programs and assert what they COMPUTE — no Elixir oracle in the loop.
  # The spec is the expected value, not `Rian.Decl`/`Rian.Beam`. This is the
  # Rian-first loop: a failing case here is a feature to add to the *Rian* sources.
  #
  # Known gaps (the backlog — programs `build` cannot yet compile, so they are not
  # asserted here; add them as they land):
  #   * lambdas / function captures — selfhost_beam emits no fun forms yet.
  #   * maps — no map-literal lowering in the driver / backend.

  setup_all do
    for {mod, file} <- [
          {"SelfhostLexerV2", "selfhost_lexer_v2"},
          {"SelfhostDecl", "selfhost_decl"},
          {"SelfhostBeam", "selfhost_beam"},
          {"SelfhostExhaust", "selfhost_exhaust"},
          {"SelfhostCap", "selfhost_cap"}
        ] do
      {:ok, _} = Beam.load(File.read!("examples/rian/#{file}.rian"), :"Elixir.#{mod}")
    end

    {:ok, drv} =
      Beam.load(File.read!("examples/rian/selfhost_compose_real_sum.rian"), :rian_selfhost_build)

    {:ok, drv: drv}
  end

  defp run(drv, src, fun, args) do
    mod = drv.build(src, :"rian_built_#{System.unique_integer([:positive])}")
    apply(mod, fun, args)
  end

  # {name, source, fun, args, expected} — each compiled + run by the self-hosted compiler.
  @programs [
    {"arithmetic", "def double(n Int53) Int53 := n * 2", :double, [5], 10},
    {"multi-clause recursion",
     "def fib(n Int53) Int53\ndef fib(0) := 0\ndef fib(1) := 1\ndef fib(n) := fib(n - 1) + fib(n - 2)",
     :fib, [10], 55},
    {"when guard",
     "def sign(n Int53) Int53\ndef sign(0) := 0\ndef sign(n) when n > 0 := 1\ndef sign(_) := -1",
     :sign, [-3], -1},
    {"if-expression", "def maxi(a Int53, b Int53) Int53 := if a > b do a else b end", :maxi,
     [3, 9], 9},
    {"sum type + ctor pattern",
     "type Opt := None | Some(Int53)\npub def get(o Opt, d Int53) Int53\n" <>
       "def get(None, d) := d\ndef get(Some(v), _) := v", :get, [{:some, 7}, 0], 7},
    {"cons-list recursion",
     "def len(xs Vec(Int53)) Int53\ndef len([]) := 0\ndef len([_ | t]) := 1 + len(t)", :len,
     [[1, 2, 3]], 3},
    {"string literal", "def tag() String := \"ok\"", :tag, [], "ok"},
    {"string `<>`", "def cat(a String, b String) String := a <> b", :cat, ["x", "y"], "xy"},
    {"case", "def cls(n Int53) Int53 := case n do\n  0 -> 100\n  m -> m\nend", :cls, [0], 100},
    {"Prim", "def cc(c Char) Int53 := Prim.char_code(c)", :cc, [?A], 65},
    {"alias", "alias N := Int53\ndef f(x N) N := x", :f, [5], 5},
    {"struct construct + field",
     "struct P(x Int53)\ndef mk(n Int53) Int53\n  p := P(x: n)\n  p.x\nend", :mk, [5], 5},
    {"tuple", "def pr(a Int53, b Int53) Tuple := {a, b}", :pr, [1, 2], {1, 2}},
    # `with` (ADR-0039): the parser keeps it as a node, the driver's lowering
    # desugars it to nested `case`. A clause that matches continues; a non-match
    # falls to the `else` arms, or (no `else`) returns the value.
    {"with (clause matches -> body)",
     "def f(p Tuple) Int53 := with {:ok, v} <- p do v else _ -> 0 end", :f, [{:ok, 5}], 5},
    {"with (clause fails -> else)",
     "def f(p Tuple) Int53 := with {:ok, v} <- p do v else _ -> 0 end", :f, [{:error, :bad}], 0},
    {"with (no else -> passthrough)", "def f(p Tuple) Int53 := with {:ok, v} <- p do v end", :f,
     [{:error, :bad}], {:error, :bad}},
    {"with (multi-clause, all match)",
     "def f(p Tuple, q Tuple) Int53 := with {:ok, a} <- p, {:ok, b} <- q do a + b else _ -> 0 end",
     :f, [{:ok, 3}, {:ok, 4}], 7},
    {"with (multi-clause, 2nd fails -> else)",
     "def f(p Tuple, q Tuple) Int53 := with {:ok, a} <- p, {:ok, b} <- q do a + b else _ -> 0 end",
     :f, [{:ok, 3}, {:error, :x}], 0}
  ]

  describe "the self-hosted Rian compiler compiles + runs real programs (no Elixir oracle)" do
    for {name, src, fun, args, want} <- @programs do
      @src src
      @fun fun
      @args args
      @want want
      test "#{name}", %{drv: drv} do
        assert run(drv, @src, @fun, @args) == @want
      end
    end
  end
end

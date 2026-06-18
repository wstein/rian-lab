defmodule Rian.EffectsTest do
  # The `@effects(...)` surface effect annotation (ADR-0048/0081): grammar
  # (`Rian.Decl`), inference (`Rian.Reach.effect_sets/1`), and the exact
  # declare-public check (`Rian.Check`). Covers the taxonomy
  # `host`/`spawn`/`io`/`fs`/`clock`/`random`/`net` — world categories are inferred
  # alongside `host` for known FFI modules.
  use ExUnit.Case, async: true

  alias Rian.{Check, Decl, Reach}

  defp parse(src), do: Decl.parse(src)
  defp effects(src), do: src |> parse() |> Reach.effect_sets()
  defp eff(report, key), do: report |> Map.fetch!(key) |> MapSet.to_list() |> Enum.sort()

  describe "@effects(...) grammar (ADR-0048 §2 / ADR-0081 §1)" do
    test "attaches the declared effect set to the function" do
      %{funcs: [f]} =
        parse("@effects(host)\npub def fmt(x String) String := Code.format_string!(x)")

      assert f.effects == [:host]
    end

    test "accepts multiple effects and dedups" do
      %{funcs: [f]} = parse("@effects(host, spawn, host)\npub def f(x Int53) Int53 := g(x)")
      assert f.effects == [:host, :spawn]
    end

    test "rejects an unknown effect name (no silently-unverified declaration)" do
      assert_raise Decl.Error, ~r/unknown\/unsupported effect `telepathy`/, fn ->
        parse("@effects(telepathy)\npub def f() Int53 := 1")
      end
    end

    test "rejects an empty effect list" do
      assert_raise Decl.Error, ~r/needs at least one effect/, fn ->
        parse("@effects()\npub def f() Int53 := 1")
      end
    end

    test "may only precede a `def`" do
      assert_raise Decl.Error, ~r/may only precede a `def`/, fn ->
        parse("@effects(host)\ntype T := A | B")
      end
    end

    test "rejects a comma-less effect list (the surface is comma-separated)" do
      assert_raise Decl.Error, ~r/expected `,` between effects/, fn ->
        parse("@effects(host spawn)\npub def f() Int53 := 1")
      end
    end

    test "rejects a stray operator between effects (no silently-skipped tokens)" do
      assert_raise Decl.Error, ~r/expected `,` between effects/, fn ->
        parse("@effects(host + spawn)\npub def f() Int53 := 1")
      end
    end

    test "rejects a non-name in effect-name position" do
      assert_raise Decl.Error, ~r/expected an effect name/, fn ->
        parse("@effects(1)\npub def f() Int53 := 1")
      end
    end

    test "effect_names/0 is the ADR-0048 §2 taxonomy" do
      assert Reach.effect_names() == [:host, :spawn, :io, :fs, :clock, :random, :net]
    end
  end

  describe "Reach.effect_sets/1 inference (ADR-0048 §3)" do
    test "a host-FFI call carries `host`" do
      assert eff(effects("pub def fmt(x String) String := Code.format_string!(x)"), "fmt/1") ==
               [:host]
    end

    test "a pure function has the empty effect set" do
      assert eff(effects("pub def id(x Int53) Int53 := x"), "id/1") == []
    end

    test "a concurrency primitive carries `spawn`" do
      assert eff(effects("pub def go(x Int53) Int53 := :erlang.spawn(x)"), "go/1") == [:spawn]
    end

    test "a known host module also carries its world category (alongside host)" do
      # a raw FFI call is non-portable (`host`) AND touches a world (`io`/`fs`/…), so it
      # carries both; the category stands alone only with a portable stdlib (ADR-0047).
      assert eff(effects("pub def p(x String) Symbol := IO.puts(x)"), "p/1") == [:host, :io]
      assert eff(effects("pub def r(x String) String := File.read(x)"), "r/1") == [:fs, :host]

      assert eff(effects("pub def g(x Int53) Int53 := :rand.uniform(x)"), "g/1") == [
               :host,
               :random
             ]

      assert eff(effects("pub def t() Int53 := :os.system_time(:second)"), "t/0") == [
               :clock,
               :host
             ]
    end

    test "an uncatalogued host module is `host`-only (coarse but honest)" do
      assert eff(effects("pub def h(x String) String := :crypto.hash(x)"), "h/1") == [:host]
    end

    test "the effect propagates transitively through the call graph" do
      rep =
        effects("""
        pub def fmt(x String) String := Code.format_string!(x)
        pub def via(x String) String := fmt(x)
        """)

      assert eff(rep, "via/1") == [:host]
    end

    test "an @external function's effects are its declared set (the host body is the leaf)" do
      rep =
        effects(~S|@effects(host)
@external(:ex, "fn x -> x end")
pub def boundary(x String) String|)

      assert eff(rep, "boundary/1") == [:host]
    end
  end

  describe "Rian.Check exact declare-public verification (ADR-0081 §2)" do
    test "declared == inferred passes" do
      assert Check.check("@effects(host)\npub def fmt(x String) String := Code.format_string!(x)") ==
               :ok
    end

    test "an undeclared function is allowed (inferred, like an unannotated error set)" do
      assert Check.check("pub def fmt(x String) String := Code.format_string!(x)") == :ok
    end

    test "over-declaration is an error — exact, not ⊆ (ADR-0048 §3)" do
      {:error, msg} = Check.check("@effects(host)\npub def id(x Int53) Int53 := x")
      assert msg =~ "declares effect(s) [:host] it does not perform"
      assert msg =~ "over-declaration is not allowed"
    end

    test "under-declaration is an error" do
      src = ~S|@effects(host)
pub def both(x String) String := Code.format_string!(:erlang.spawn(x))|

      {:error, msg} = Check.check(src)
      assert msg =~ "performs effect(s) [:spawn] not in its `@effects` declaration"
    end

    test "an @external boundary's declared effect verifies (the declaration is the leaf)" do
      src = ~S|@effects(host)
@external(:ex, "fn x -> x end")
pub def boundary(x String) String|

      assert Check.check(src) == :ok
    end
  end
end

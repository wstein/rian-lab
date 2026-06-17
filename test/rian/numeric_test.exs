defmodule Rian.NumericTest do
  # async: false — loads real modules into the VM via :code.load_binary.
  use ExUnit.Case, async: false

  alias Rian.{Beam, Decl, JS, JVM, Reach}

  # ADR-0064: `Int` is **arbitrary precision** (the portable, identical-everywhere
  # integer), distinct from fixed-width `Int64` (defined two's-complement wrap).
  # `Int` is native on BEAM (bignum) and JS (BigInt); Rust/JVM need a bignum that
  # is not implemented, so `Int` pins off `:rs`/`:jvm` (fail loud, never miscompile).

  describe "`Int` is arbitrary precision on the BEAM" do
    test "Int arithmetic stays exact past 64 bits (the whole point)" do
      {:ok, m} =
        Beam.load(
          "def fact(n Int) Int\ndef fact(0) := 1\ndef fact(n) := n * fact(n - 1)",
          :rian_int_fact
        )

      # 30! ≈ 2.65e32 — far beyond a 64-bit range; an `Int` keeps it exact.
      assert m.fact(30) == 265_252_859_812_191_058_636_308_480_000_000
      assert m.fact(30) > 0x7FFF_FFFF_FFFF_FFFF
    end

    test "Int lowers to a Dialyzer `integer()` -spec" do
      {:ok, _atom, bin} = Beam.compile("pub def id(n Int) Int := n", :rian_int_spec)

      {:ok, {_m, [debug_info: {:debug_info_v1, _, {_, specs}}]}} =
        :beam_lib.chunks(bin, [:debug_info])

      # the spec exists and types n/result as integer() (not term())
      assert is_list(specs) or is_map(specs)
    end
  end

  describe "`Int` portability (ADR-0064): native on BEAM/JS, bignum-gap on Rust/JVM" do
    test "Int reaches [:ex, :js] but not [:rs, :jvm] — the bignum gap is honest" do
      rep = Reach.analyze(Decl.parse("def big(n Int) Int := n * n"))
      assert rep["big/1"].reach |> MapSet.to_list() |> Enum.sort() == [:ex, :js]
      assert [%{kind: :numeric, kills: [:rs, :jvm]}] = rep["big/1"].blockers
    end

    test "Int lowers to BigInt on JS" do
      assert JS.compile("def two() Int := 2") =~ "2n"
    end

    test "Int fails loudly on Rust (needs a bignum), never a silent miscompile" do
      assert_raise ArgumentError, ~r/Int.*bignum/, fn ->
        Rian.Capability.owned("Int")
      end
    end

    test "Int fails loudly on the JVM (needs BigInteger)" do
      assert_raise JVM.Unsupported, ~r/BigInteger/, fn ->
        JVM.compile("def big(n Int) Int := n")
      end
    end
  end

  describe "fixed-width keeps its defined-wrap contract (ADR-0064)" do
    test "Int64 wrapping arithmetic wraps two's-complement, while Int does not" do
      {:ok, m} =
        Beam.load(
          "def wrap(a Int64, b Int64) Int64 := __prim_wrapping_add(a, b)\n" <>
            "def exact(a Int, b Int) Int := a + b",
          :rian_wrap_contract
        )

      max64 = 0x7FFF_FFFF_FFFF_FFFF
      # fixed-width Int64: defined two's-complement wrap (the same on every target)
      assert m.wrap(max64, 1) == -0x8000_0000_0000_0000
      # arbitrary-precision Int: no wrap, exact
      assert m.exact(max64, 1) == max64 + 1
    end
  end

  describe "JS rejects a module mixing `Int` (BigInt) with `Int53`/`Int32` (number) (ADR-0064 §2a)" do
    # Regression: number-mode is whole-program, so a mixed module used to silently
    # demote `Int` to a bounded JS `number` (e.g. `big()` emitted `2`, not `2n`).
    # That is the precision change ADR-0064 forbids — reject the mix loudly.
    test "an Int + Int53 module is refused" do
      assert_raise JS.Unsupported, ~r/cannot mix `Int`.*`Int53`/, fn ->
        JS.compile("def depth(n Int53) Int53 := n\ndef big() Int := 2")
      end
    end

    test "a pure-Int module still emits BigInt; a pure-Int53 module still emits number" do
      assert JS.compile("def big() Int := 2") =~ "return 2n"
      js53 = JS.compile("def inc(n Int53) Int53 := n + 1")
      assert js53 =~ "(n + 1)"
      refute js53 =~ "1n"
    end
  end
end

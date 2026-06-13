defmodule Rian.RangeTest do
  # async: false — the BEAM cases load real modules into the VM.
  use ExUnit.Case, async: false

  alias Rian.{Beam, Decl}
  alias Rian.IR.Range

  defp compiles?(src) do
    Decl.compile(src)
    true
  rescue
    _ -> false
  end

  describe "parsing (ADR-0036)" do
    test "`range Name := lo..hi` parses to an IR.Range over Int64" do
      assert %{ranges: [%Range{name: "Bit", base: "Int64", lo: 0, hi: 1}]} =
               Decl.parse("range Bit := 0..1")
    end

    test "a `Char` range carries codepoint bounds" do
      assert %{ranges: [%Range{name: "Az", base: "Char", lo: ?a, hi: ?z}]} =
               Decl.parse("range Az := 'a'..'z'")
    end

    test "an inverted range is rejected" do
      assert_raise Decl.Error, ~r/inverted/, fn -> Decl.parse("range Bad := 9..0") end
    end

    test "bounds must share a base" do
      assert_raise Decl.Error, ~r/share a base/, fn -> Decl.parse("range Mix := 0..'z'") end
    end
  end

  describe "finite-signature exhaustiveness (the load-bearing decision)" do
    @covered "range Bit := 0..1\ndef flip(b Bit) Bit\ndef flip(0) := 1\ndef flip(1) := 0"

    test "clause heads covering the whole interval are total — no catch-all needed" do
      assert compiles?(@covered)
    end

    test "missing a member is non-exhaustive — the gate refuses to emit" do
      refute compiles?("range Bit := 0..1\ndef flip(b Bit) Bit\ndef flip(0) := 1")
    end

    test "a catch-all after full coverage is an unreachable (dead) clause" do
      refute compiles?(@covered <> "\ndef flip(_) := 0")
    end

    test "the same literal heads over a bare Int64 stay non-exhaustive (no range)" do
      # without the `range` declaration, `0`/`1` leave the witness `_` open
      refute compiles?("def flip(b Int64) Int64\ndef flip(0) := 1\ndef flip(1) := 0")
    end
  end

  describe "execution and lowering" do
    test "a range-typed function runs on real BEAM bytecode" do
      {:ok, m} = Beam.load(@covered, :rian_range_bit)
      assert {m.flip(0), m.flip(1)} == {1, 0}
    end

    test "a Char range runs on the BEAM (members are codepoints)" do
      src = "range AB := 'a'..'b'\ndef tag(c AB) Int64\ndef tag('a') := 1\ndef tag('b') := 2"
      {:ok, m} = Beam.load(src, :rian_range_ab)
      assert {m.tag(?a), m.tag(?b)} == {1, 2}
    end

    test "the range type resolves to its base primitive in the emitted Rust" do
      [{_, %{rust: rust}}] = Decl.compile(@covered)
      # `Bit` -> `i64`, plus the ADR-0036 exhaustiveness shim over the open base
      assert rust =~ "fn flip(b: i64) -> i64"
      assert rust =~ "_ => unreachable!(),"
    end

    @tag :rust
    test "the range Rust lowering compiles and runs under rustc" do
      case System.find_executable("rustc") do
        nil ->
          :ok

        rustc ->
          [{_, %{rust: rust}}] = Decl.compile(@covered)
          dir = System.tmp_dir!()
          src = Path.join(dir, "rian_range_#{System.unique_integer([:positive])}.rs")
          bin = String.trim_trailing(src, ".rs")
          File.write!(src, "#{rust}\nfn main() { println!(\"{} {}\", flip(0), flip(1)); }")
          {_, 0} = System.cmd(rustc, ["--edition", "2021", src, "-o", bin])
          assert {"1 0\n", 0} = System.cmd(bin, [])
      end
    end

    @tag :rust
    test "implicit Char arithmetic lowers to `char as i64` casts and runs under rustc" do
      case System.find_executable("rustc") do
        nil ->
          :ok

        rustc ->
          [{_, %{rust: rust}}] = Decl.compile("def dval(c Char) Int64 := c - '0'")
          # the native `char` operands are widened to their codepoint base
          assert rust =~ "(c as i64) - ('0' as i64)"

          dir = System.tmp_dir!()
          src = Path.join(dir, "rian_chararith_#{System.unique_integer([:positive])}.rs")
          bin = String.trim_trailing(src, ".rs")
          File.write!(src, "#{rust}\nfn main() { println!(\"{}\", dval('7')); }")
          {_, 0} = System.cmd(rustc, ["--edition", "2021", src, "-o", bin])
          assert {"7\n", 0} = System.cmd(bin, [])
      end
    end
  end
end

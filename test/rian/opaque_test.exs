defmodule Rian.OpaqueTest do
  @moduledoc """
  `opaque T := Base` — abstract (nominal, zero-cost) types (ADR-0067 / ADR-0043).

  The type is **distinct from its base** to `Rian.Check` (a raw `Base` where a `T`
  is expected, or vice versa, is a type error) but **erases to `Base`** on every
  target: `Rian.Opaque.erase/1`, run after the gates, substitutes `T -> Base` in
  all type positions and rewrites the total constructor `T.of(x)` to the bare `x`.
  """
  use ExUnit.Case, async: false

  alias Rian.{Check, Decl, Opaque}

  describe "parsing" do
    test "`opaque T := Base` registers a nominal type with its base" do
      prog = Decl.parse("opaque Token := String")
      assert [%Rian.IR.Opaque{name: "Token", base: "String", pub?: false}] = prog.opaques
    end

    test "`pub opaque` is exported" do
      prog = Decl.parse("opaque Secret := Int64\npub opaque Token := String")

      assert %Rian.IR.Opaque{name: "Token", pub?: true} =
               Enum.find(prog.opaques, &(&1.name == "Token"))
    end

    test "an opaque inside a `mod` is scoped to that module" do
      prog = Decl.parse("mod M do\n  opaque Token := String\nend")
      assert [%Rian.IR.Opaque{name: "Token", base: "String"}] = hd(prog.mods).opaques
    end

    test "an opaque without `:=` is an error" do
      assert_raise Decl.Error, ~r/opaque declaration needs `:=`/, fn ->
        Decl.parse("opaque Token")
      end
    end
  end

  describe "checking (nominal distinctness, ADR-0043)" do
    test "`T.of(x)` is the total constructor — `x : Base` yields `T`" do
      assert Check.check("opaque Token := String\ndef wrap(s String) Token := Token.of(s)") == :ok
    end

    test "a raw `Base` where `T` is expected is rejected" do
      assert {:error, msg} = Check.check("opaque Token := String\ndef wrap(s String) Token := s")
      assert msg =~ "Token"
    end

    test "a `T` where the `Base` is expected is rejected (the reverse direction)" do
      assert {:error, msg} = Check.check("opaque Token := String\ndef f(t Token) String := t")
      assert msg =~ "String"
    end

    test "two opaques over the same base are distinct from each other" do
      src = """
      opaque Token := String
      opaque Name := String

      def f(t Token) Name := t
      """

      assert {:error, _} = Check.check(src)
    end
  end

  describe "erasure (Rian.Opaque.erase/1)" do
    test "substitutes the opaque name to its base in params and return" do
      prog = Opaque.erase(Decl.parse("opaque Token := String\ndef wrap(s Token) Token := s"))
      f = hd(prog.funcs)
      assert [%{name: "s", type: "String"}] = f.params
      assert f.ret == "String"
    end

    test "rewrites `T.of(x)` to the bare `x` in the clause body" do
      prog =
        Opaque.erase(
          Decl.parse("opaque Token := String\ndef wrap(s String) Token := Token.of(s)")
        )

      assert {:block, [expr: {:id, "s"}]} = hd(hd(prog.funcs).clauses).body
    end

    test "leaves a non-opaque `.of` (a range constructor) intact" do
      # an opaque is present so erasure runs (and parses bodies); the range's `.of`
      # must survive — only an *opaque* `.of` is the identity, a range's is a real call.
      src = "opaque Tok := String\nrange Digit := 0..9\ndef d(n Int64) Int64 := Digit.of(n)"
      prog = Opaque.erase(Decl.parse(src))
      body = hd(hd(prog.funcs).clauses).body
      assert {:block, [expr: {:call, {:dot, {:id, "Digit"}, "of"}, _}]} = body
    end

    test "a program with no opaques is returned unchanged" do
      prog = Decl.parse("def id(x Int64) Int64 := x")
      assert Opaque.erase(prog) == prog
    end

    test "erases inside a `mod`" do
      prog =
        Opaque.erase(
          Decl.parse("mod M do\n  opaque Token := String\n  def wrap(s Token) Token := s\nend")
        )

      f = hd(hd(prog.mods).funcs)
      assert [%{type: "String"}] = f.params
      assert f.ret == "String"
    end
  end

  describe "emit (zero-cost on every Tier-1 target)" do
    @src """
    opaque Token := String

    def wrap(s String) Token := Token.of(s)
    def echo(t Token) Token := t
    """

    test "BEAM: `T.of(x)` round-trips the bare base value" do
      {:ok, mod, bin} = Rian.Beam.compile(@src, :"rian_opq_#{System.unique_integer([:positive])}")
      {:module, ^mod} = :code.load_binary(mod, ~c"#{mod}.beam", bin)
      assert apply(mod, :wrap, ["hi"]) == "hi"
      assert apply(mod, :echo, ["yo"]) == "yo"
    end

    test "Rust: the opaque emits as its base type, no `.of` call" do
      rust = Rian.Lower.rust_program(Decl.parse(@src))
      assert rust =~ "fn echo(t: &str) -> String"
      refute rust =~ "Token"
      refute rust =~ ".of("
    end

    test "JS: the opaque erases entirely (no `Token`, no `.of`)" do
      js = Rian.JS.compile(@src)
      refute js =~ "Token"
      refute js =~ ".of("
    end

    test "JVM: the opaque emits as its base type" do
      kt = Rian.JVM.compile(@src)
      assert kt =~ "fun echo(a0: String): String"
      refute kt =~ "Token"
    end
  end
end

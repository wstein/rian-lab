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

  describe "abstract — operators (ADR-0067 P1b) and casts (P1c)" do
    @abs """
    abstract Meters := Float64 do
      op +(a Meters, b Meters) Meters
      to base() Float64
    end

    def add(a Meters, b Meters) Meters := a + b
    def raw(m Meters) Float64 := m.base()
    """

    test "the `do … end` block parses into `op` rules and `to` casts" do
      [m] = Decl.parse(@abs).opaques
      assert m.name == "Meters" and m.base == "Float64"
      assert m.ops == [%{op: "+", params: ["Meters", "Meters"], ret: "Meters"}]
      assert m.casts == [%{name: "base", ret: "Float64"}]
    end

    test "a declared operator types `Meters + Meters` as `Meters`" do
      assert Check.check(@abs) == :ok
    end

    test "the operator yields the nominal type, not the base (no implicit decay, ADR-0035)" do
      bad = """
      abstract Meters := Float64 do
        op +(a Meters, b Meters) Meters
      end

      def add(a Meters, b Meters) Float64 := a + b
      """

      assert {:error, msg} = Check.check(bad)
      assert msg =~ "Meters" and msg =~ "Float64"
    end

    test "an abstract over `Int64` (not just Float64) overloads its operator" do
      src = """
      abstract Count := Int64 do
        op +(a Count, b Count) Count
      end

      def bump(a Count, b Count) Count := a + b
      """

      assert Check.check(src) == :ok
    end

    test "an `abstract` without a `do … end` block is an error" do
      assert_raise Decl.Error, ~r/abstract.*do.*end/, fn ->
        Decl.parse("abstract Meters := Float64")
      end
    end

    test "BEAM: operators and casts erase — `add`/`raw` compute on the base value" do
      {:ok, mod, bin} = Rian.Beam.compile(@abs, :"rian_abs_#{System.unique_integer([:positive])}")
      {:module, ^mod} = :code.load_binary(mod, ~c"#{mod}.beam", bin)
      assert apply(mod, :add, [1.5, 2.0]) == 3.5
      assert apply(mod, :raw, [3.5]) == 3.5
    end

    test "Rust: the abstract erases to its base, operator is the native `+`, cast is identity" do
      rust = Rian.Lower.rust_program(Decl.parse(@abs))
      assert rust =~ "fn add(a: f64, b: f64) -> f64"
      assert rust =~ "a + b"
      assert rust =~ "fn raw(m: f64) -> f64"
      refute rust =~ "Meters"
      refute rust =~ ".base("
    end

    test "JS and JVM: the abstract erases entirely" do
      js = Rian.JS.compile(@abs)
      refute js =~ "Meters"
      refute js =~ ".base("

      kt = Rian.JVM.compile(@abs)
      assert kt =~ "fun add(a0: Double, a1: Double): Double"
      refute kt =~ "Meters"
    end

    test "a cast `.base()` strips only on the declaring abstract's value (type-scoped, §2)" do
      # `m : Meters` declares `base`, so `m.base()` strips to `m`.
      src = "abstract Meters := Float64 do\n  to base() Float64\nend\ndef raw(m Meters) Float64 := m.base()"
      body = hd(hd(Opaque.erase(Decl.parse(src)).funcs).clauses).body
      assert {:block, [expr: {:id, "m"}]} = body
    end

    test "a cast name matched on an unrelated type is NOT stripped (name match alone is insufficient)" do
      # `s : String` does not declare `base`; only the name collides. The cast must
      # survive — stripping it by name would silently miscompile `something.base()`.
      src = "abstract Meters := Float64 do\n  to base() Float64\nend\ndef raw(s String) String := s.base()"
      body = hd(hd(Opaque.erase(Decl.parse(src)).funcs).clauses).body
      assert {:block, [expr: {:call, {:dot, {:id, "s"}, "base"}, []}]} = body
    end
  end

  describe "erasure of an opaque referenced inside other declarations" do
    test "an opaque inside a sum variant's field erases to the base" do
      prog = Opaque.erase(Decl.parse("opaque Token := String\ntype Wrap := W(Token)"))
      [%Rian.IR.Type{variants: [%Rian.IR.Variant{ctor: "W", fields: [field]}]}] = prog.types
      assert field.type == "String"
    end

    test "an opaque inside a struct field erases to the base" do
      prog = Opaque.erase(Decl.parse("opaque Token := String\nstruct S(t Token)"))
      [%Rian.IR.Struct{fields: [field]}] = prog.structs
      assert %Rian.IR.Field{label: "t", type: "String"} = field
    end

    test "an opaque as a `const`'s declared type erases to the base" do
      src = "opaque Token := String\nmod M do\n  const C Token := x\nend"
      prog = Opaque.erase(Decl.parse(src))
      [%Rian.IR.Const{name: "C", type: type}] = hd(prog.mods).consts
      assert type == "String"
    end

    test "opaque-over-opaque resolves transitively to the concrete base (order-independent)" do
      # `A := B`, `B := Int64`: a single simultaneous pass would leave `A` at `B`.
      # The fixpoint resolves `A` straight to `Int64` regardless of declaration order.
      [out] = Opaque.erase(Decl.parse("opaque A := B\nopaque B := Int64\ndef f(x A) A := x")).funcs
      assert [%Rian.IR.Param{type: "Int64"}] = out.params
      assert out.ret == "Int64"
    end

    test "transitive erasure reaches compound types regardless of declaration order" do
      # Reverse order (base-first), inside a `Vec(...)`: still collapses to `Vec(Int64)`.
      src = "opaque B := Int64\nopaque A := B\nstruct S(xs Vec(A))"
      [%Rian.IR.Struct{fields: [field]}] = Opaque.erase(Decl.parse(src)).structs
      assert field.type == "Vec(Int64)"
    end
  end

  describe "erasure edge cases (nil slots, non-cast dot-calls)" do
    test "a signature-only clause (nil body) and a nil return type are passed through" do
      # Built directly: the parser rejects a signature-only top-level `def`, but the
      # IR can carry a `%Clause{body: nil}` (and a `nil` ret) which erasure must leave intact.
      f = %Rian.IR.Func{
        name: "f",
        params: [%Rian.IR.Param{name: "s", type: "Token"}],
        ret: nil,
        clauses: [%Rian.IR.Clause{pats: [], body: nil}]
      }

      prog = %{opaques: [%Rian.IR.Opaque{name: "Token", base: "String"}], funcs: [f]}
      [out] = Opaque.erase(prog).funcs

      # param type still substitutes; the nil body and nil ret survive untouched.
      assert [%Rian.IR.Param{type: "String"}] = out.params
      assert out.ret == nil
      assert [%Rian.IR.Clause{body: nil}] = out.clauses
    end

    test "a non-cast, non-`.of` zero-arg dot-call is preserved (generic recursion)" do
      # `x.foo()` is neither an opaque `.of` constructor nor a declared cast, so it
      # must fall through `strip_into` and survive erasure unchanged.
      prog = Opaque.erase(Decl.parse("opaque Token := String\ndef g(x Int64) Int64 := x.foo()"))
      body = hd(hd(prog.funcs).clauses).body
      assert {:block, [expr: {:call, {:dot, {:id, "x"}, "foo"}, []}]} = body
    end
  end
end

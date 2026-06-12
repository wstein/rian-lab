defmodule Rian.ReplTest do
  # Not async: each entry compiles + loads a BEAM module.
  use ExUnit.Case, async: false

  import ExUnit.CaptureIO

  alias Rian.Repl

  defp eval(session, input), do: Repl.eval(session, input)

  describe "expressions" do
    test "evaluates arithmetic with its inferred type" do
      assert {{:value, 2, "Int64"}, _s} = eval(Repl.new(), "1 + 1")
    end

    test "evaluates lists, tuples, and atoms" do
      assert {{:value, [1, 2, 3], _}, _} = eval(Repl.new(), "[1, 2, 3]")
      assert {{:value, {1, 2}, _}, _} = eval(Repl.new(), "{1, 2}")
    end

    test "evaluates a case expression" do
      src = "case 1 do\n  0 -> :zero\n  _ -> :other\nend"
      assert {{:value, :other, _}, _} = eval(Repl.new(), src)
    end

    test "blank input is empty and leaves the session untouched" do
      s = Repl.new()
      assert {:empty, ^s} = eval(s, "   ")
    end
  end

  describe "declarations" do
    test "defines a function, then calls it" do
      s = Repl.new()
      assert {{:defined, ["sq"]}, s} = eval(s, "def sq(n Int64) Int64\ndef sq(n) := n * n")
      # A local call to a session function infers its declared return type
      # (no more bare `49` — the prompt prints `49 : Int64`).
      assert {{:value, 49, "Int64"}, _} = eval(s, "sq(7)")
    end

    test "a bind whose RHS calls a session function records that function's return type" do
      s = Repl.new()
      {{:defined, ["sq"]}, s} = eval(s, "def sq(n Int64) Int64\ndef sq(n) := n * n")
      assert {{:bound, "y", 9, "Int64"}, _} = eval(s, "y := sq(3)")
    end

    test "a sum-type constructor infers the type the variant builds" do
      s = Repl.new()
      {{:defined, ["Bit"]}, s} = eval(s, "type Bit := Zero | One")
      assert {{:value, :one, "Bit"}, _} = eval(s, "One")
    end

    test "a generic function's return concretizes to the call's argument type" do
      s = Repl.new()
      {{:defined, ["id"]}, s} = eval(s, "def id(x T) T forall T\ndef id(x) := x")
      # `forall T` no longer collapses to bare `:unknown` at the prompt —
      # `id(5)` reads its `T` from the argument's `Int64` (ADR-0042).
      assert {{:value, 5, "Int64"}, _} = eval(s, "id(5)")
    end

    test "redefines a function (shadowing, not duplication)" do
      s = Repl.new()
      {{:defined, ["f"]}, s} = eval(s, "def f(n Int64) Int64\ndef f(n) := n + 1")
      assert {{:value, 4, _}, s} = eval(s, "f(3)")
      {{:defined, ["f"]}, s} = eval(s, "def f(n Int64) Int64\ndef f(n) := n * 10")
      assert {{:value, 30, _}, _} = eval(s, "f(3)")
    end

    test "defines a sum type and constructs/matches its variants" do
      s = Repl.new()
      {{:defined, ["Bit"]}, s} = eval(s, "type Bit := Zero | One")

      {{:defined, ["flip"]}, s} =
        eval(s, "def flip(b Bit) Bit\ndef flip(Zero) := One\ndef flip(One) := Zero")

      assert {{:value, :zero, _}, _} = eval(s, "flip(One)")
    end
  end

  describe "top-level bindings" do
    test "binds a value, visible to a later expression" do
      s = Repl.new()
      assert {{:bound, "x", 5, "Int64"}, s} = eval(s, "x := 5")
      assert {{:value, 6, "Int64"}, _} = eval(s, "x + 1")
    end

    test "a later bind of the same name shadows the earlier" do
      s = Repl.new()
      {{:bound, "x", 5, _}, s} = eval(s, "x := 5")
      {{:bound, "x", 9, _}, s} = eval(s, "x := 9")
      assert {{:value, 9, _}, _} = eval(s, "x")
    end
  end

  describe "typed bindings (ADR-0034 §1)" do
    test "a numeric literal adopts the declared width, displayed at that type" do
      assert {{:bound, "x", 66, "Int32"}, s} = eval(Repl.new(), "x Int32 := 66")
      # the adopted type is visible to a later expression
      assert {{:value, 67, _}, _} = eval(s, "x + 1")
    end

    test "a float literal adopts a float-width annotation" do
      assert {{:bound, "f", 6.5, "Float32"}, _} = eval(Repl.new(), "f Float32 := 6.5")
    end

    test "a literal whose annotation is not a matching width is a binding-site error" do
      assert {{:error, msg}, s} = eval(Repl.new(), "x Bool := 66")
      assert msg =~ "declared `Bool`"
      assert msg =~ "Int64"
      # the failed binding does not advance the session
      assert {{:error, _}, ^s} = eval(s, "x")
    end

    test "an integer literal does not adopt a float annotation" do
      assert {{:error, _}, _} = eval(Repl.new(), "x Float64 := 66")
    end

    test "an already-typed value must unify exactly with the annotation" do
      s = Repl.new()
      {{:bound, "x", 66, "Int32"}, s} = eval(s, "x Int32 := 66")
      assert {{:bound, "y", 66, "Int32"}, s} = eval(s, "y Int32 := x")
      assert {{:error, msg}, _} = eval(s, "z Int64 := x")
      assert msg =~ "declared `Int64`"
    end

    test "untyped bindings are unaffected" do
      assert {{:bound, "x", 66, "Int64"}, _} = eval(Repl.new(), "x := 66")
    end
  end

  describe "errors leave the session unchanged" do
    test "a parse error is reported and the session is untouched" do
      s = Repl.new()
      assert {{:error, _message}, ^s} = eval(s, "1 +")
    end

    test "a runtime error is reported and the session is untouched" do
      s = Repl.new()
      assert {{:error, message}, ^s} = eval(s, "1 + true")
      assert message != ""
    end
  end

  describe "engine contract" do
    test "eval/2 performs no IO (stdout, stderr) across success and error paths" do
      run = fn ->
        s = Repl.new()
        {_, s} = eval(s, "1 + 1")
        {_, s} = eval(s, "def f(n Int64) Int64\ndef f(n) := n + 1")
        {_, s} = eval(s, "f(10)")
        {_, s} = eval(s, "x := 7")
        {_, s} = eval(s, "x + f(x)")
        # error paths
        {_, s} = eval(s, "1 +")
        {_, _} = eval(s, "1 + true")
        s
      end

      assert capture_io(run) == ""
      assert capture_io(:stderr, run) == ""
    end
  end

  describe "session resource usage" do
    test "many evals reuse a single BEAM module (no atom or code leak)" do
      n = 200
      s0 = Repl.new()
      prefix = "rian_repl_#{s0.base}"
      module = String.to_atom(prefix)

      assert session_module_count(prefix) == 0

      Enum.reduce(1..n, s0, fn _, s ->
        {{:value, 2, _}, s2} = eval(s, "1 + 1")
        s2
      end)

      # Exactly one module is loaded for the session regardless of n.
      assert session_module_count(prefix) == 1
      assert :code.is_loaded(module) != false
    end
  end

  defp session_module_count(prefix) do
    legacy_prefix = prefix <> "_"

    Enum.count(:code.all_loaded(), fn {m, _} ->
      name = Atom.to_string(m)
      name == prefix or String.starts_with?(name, legacy_prefix)
    end)
  end

  describe "info/1 — session introspection" do
    test "a fresh session is empty" do
      assert Repl.info(Repl.new()) == %{defined: [], bound: []}
    end

    test "reports defined names and bound names in order" do
      s = Repl.new()
      {_, s} = eval(s, "def sq(n Int64) Int64\ndef sq(n) := n * n")
      {_, s} = eval(s, "x := 5")
      {_, s} = eval(s, "y := 9")
      assert Repl.info(s) == %{defined: ["sq"], bound: ["x", "y"]}
    end

    test "a sum type's name shows under defined" do
      s = Repl.new()
      {_, s} = eval(s, "type Bit := Zero | One")
      assert %{defined: defined} = Repl.info(s)
      assert "Bit" in defined
    end

    test "a redefinition and a rebind each appear once" do
      s = Repl.new()
      {_, s} = eval(s, "x := 1")
      {_, s} = eval(s, "x := 2")
      assert Repl.info(s) == %{defined: [], bound: ["x"]}
    end
  end

  describe "type_of/2 — type without evaluation" do
    test "infers an expression's type" do
      assert Repl.type_of(Repl.new(), "1 + 2") == "Int64"
    end

    test "uses the session's bindings" do
      s = Repl.new()
      {_, s} = eval(s, "x := 10")
      assert Repl.type_of(s, "x + 1") == "Int64"
    end

    test "returns nil when no type can be inferred" do
      assert Repl.type_of(Repl.new(), "f(1)") == nil
    end

    test "performs no IO and does not run the expression" do
      s = Repl.new()
      run = fn -> Repl.type_of(s, "1 + 1") end
      assert capture_io(run) == ""
      assert capture_io(:stderr, run) == ""
      # Purely a read: the same session still answers the same way.
      assert Repl.type_of(s, "1 + 1") == "Int64"
    end
  end

  describe "complete/2 — Rian-aware tab-completion" do
    test "completes a keyword from a prefix" do
      assert {["def"], "f"} = Repl.complete("de", Repl.new())
    end

    test "an empty trailing token offers nothing to append" do
      assert {_candidates, ""} = Repl.complete("1 + ", Repl.new())
    end

    test "a `\\`-token completes against meta-commands only" do
      {candidates, completion} = Repl.complete("\\t", Repl.new())
      assert candidates == ["\\type"]
      assert completion == "ype"
    end

    test "lists meta-commands sharing a prefix without a spurious append" do
      {candidates, completion} = Repl.complete("\\", Repl.new())
      assert "\\help" in candidates and "\\env" in candidates
      assert completion == ""
    end

    test "completes session-defined names" do
      s = Repl.new()
      {_, s} = eval(s, "def square(n Int64) Int64\ndef square(n) := n * n")
      {candidates, completion} = Repl.complete("squ", s)
      assert candidates == ["square"]
      assert completion == "are"
    end

    test "completes session-bound names" do
      s = Repl.new()
      {_, s} = eval(s, "total := 42")
      assert {["total"], "al"} = Repl.complete("tot", s)
    end

    test "no match yields no candidates and nothing to append" do
      assert {[], ""} = Repl.complete("zzzq", Repl.new())
    end

    test "appends only the shared continuation when candidates diverge" do
      # `i` matches `if` and `in` — shared prefix is just `i`, nothing to add.
      {candidates, completion} = Repl.complete("i", Repl.new())
      assert "if" in candidates and "in" in candidates
      assert completion == ""
    end

    test "is pure — performs no IO" do
      s = Repl.new()
      assert capture_io(fn -> Repl.complete("de", s) end) == ""
    end
  end

  describe "describe/1 — session signature metadata" do
    test "reports a function's arity and return type" do
      s = Repl.new()
      {_, s} = eval(s, "def square(n Int64) Int64\ndef square(n) := n * n")
      assert %{functions: %{"square" => {1, "Int64"}}} = Repl.describe(s)
    end

    test "reports a bind's inferred type" do
      s = Repl.new()
      {_, s} = eval(s, "total := 42")
      assert %{binds: %{"total" => "Int64"}} = Repl.describe(s)
    end

    test "a fresh session has no functions or binds" do
      assert Repl.describe(Repl.new()) == %{functions: %{}, binds: %{}}
    end
  end

  describe "vocabulary/0 — the static word list" do
    test "includes keywords, word-operators, and meta-commands" do
      vocab = Repl.vocabulary()
      assert "def" in vocab
      assert "rem" in vocab
      assert "\\type" in vocab
    end
  end

  describe "render/1 (the print phase)" do
    test "formats each result kind" do
      assert Repl.render({:value, 2, "Int64"}) == "2 : Int64"
      assert Repl.render({:value, [1, 2], nil}) == "[1, 2]"
      assert Repl.render({:bound, "x", 5, "Int64"}) == "x := 5 : Int64"
      assert Repl.render({:defined, ["sq", "Bit"]}) == "defined sq, Bit"
      assert Repl.render({:error, "boom"}) == "error: boom"
      assert Repl.render(:empty) == ""
    end
  end
end

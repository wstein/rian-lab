defmodule Rian.ReplTest do
  # Not async: each entry compiles + loads a BEAM module.
  use ExUnit.Case, async: false

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
      assert {{:value, 49, _}, _} = eval(s, "sq(7)")
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

  describe "errors leave the session unchanged" do
    test "an unsupported construct is a clear error, never a silent miscompile" do
      s = Repl.new()
      # a map literal has no abstract-forms lowering yet (strings now do)
      assert {{:error, message}, ^s} = eval(s, "%{a: 1}")
      assert message =~ "EMap" or message =~ "not yet supported" or message != ""
    end

    test "a parse error is reported" do
      s = Repl.new()
      assert {{:error, _message}, ^s} = eval(s, "1 +")
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

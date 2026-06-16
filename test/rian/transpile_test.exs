defmodule Rian.TranspileTest do
  use ExUnit.Case, async: true

  alias Rian.Transpile

  defp rian(src), do: Transpile.transpile(src)

  describe "structure that has a clear Rian image" do
    test "module + simple def → `mod`/`pub def` with type holes" do
      out = rian("defmodule M do\n  def double(x), do: x + x\nend")
      assert out =~ "mod M do"
      assert out =~ "pub def double(x _Ty) _Ret := x + x"
    end

    test "defp is private (`def`, no `pub`)" do
      assert rian("defmodule M do\n  defp f(x), do: x\nend") =~ ~r/\n  def f\(x _Ty\) _Ret :=/
    end

    test "multi-clause def emits one sig + per-clause bodies" do
      out = rian("defmodule M do\n  def f(0), do: :z\n  def f(n), do: n\nend")
      assert out =~ "pub def f(_Ty) _Ret  # TODO[port]: fill types"
      assert out =~ "pub def f(0) := :z"
      assert out =~ "pub def f(n) := n"
    end

    test "case with a ctor/struct pattern arm" do
      out = rian("""
      defmodule M do
        def g(x) do
          case x do
            %Foo{a: y} -> y
            _ -> 0
          end
        end
      end
      """)

      assert out =~ "case x do"
      assert out =~ "Foo(a: y) -> y"
      assert out =~ "_ -> 0"
    end

    test "struct CONSTRUCTION → ctor call, not malformed `%(__aliases__...)`" do
      out = rian("defmodule M do\n  def b, do: %EBin{op: \"and\", left: 1, right: 2}\nend")
      assert out =~ ~s|EBin(op: "and", left: 1, right: 2)|
      refute out =~ "__aliases__"
      refute out =~ "map literal"
    end
  end

  describe "honest quarantine — nothing untranslated masquerades as done" do
    test "remote/stdlib calls become greppable TODO_PORT markers" do
      out = rian("defmodule M do\n  def t(xs), do: Enum.map(xs, fn x -> x end)\nend")
      assert out =~ "TODO_PORT(\"remote/stdlib call:"
    end

    test "nil has no Rian image → flagged (no silent translation)" do
      assert rian("defmodule M do\n  def n, do: nil\nend") =~
               ~s|TODO_PORT("nil|
    end

    test "clause guards are surfaced as notes, never silently dropped" do
      out = rian("defmodule M do\n  def f(n) when n > 0, do: n\n  def f(_), do: 0\nend")
      assert out =~ "# TODO[port]: clause guard `when n > 0`"
    end
  end

  describe "transpile_with_stats" do
    test "counts def groups and unresolved markers" do
      {_text, stats} =
        Transpile.transpile_with_stats(
          "defmodule M do\n  def a, do: Enum.x(1)\n  def b(z), do: z\nend"
        )

      assert stats.defs == 2
      assert stats.ports >= 1
    end
  end
end

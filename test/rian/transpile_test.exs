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
      assert out =~ "pub def f(_Ty) _Ret"
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

    test "an unmapped Elixir stdlib call (Enum.map) stays a marker" do
      out = rian("defmodule M do\n  def t(xs), do: Enum.map(xs, fn x -> x end)\nend")
      assert out =~ "TODO_PORT(\"remote/stdlib call: Enum.map"
    end
  end

  describe "translations beyond the structural core" do
    test "nil → Option's None (Rian's nullable model)" do
      assert rian("defmodule M do\n  def n, do: nil\nend") =~ ":= None"
    end

    test "clause guards are translated into the Rian clause head" do
      out = rian("defmodule M do\n  def f(n) when n > 0, do: n\n  def f(_), do: 0\nend")
      assert out =~ "pub def f(n) when n > 0 := n"
    end

    test "string interpolation `\#{e}` → Rian `${e}`" do
      assert rian(~S|defmodule M do
  def g(x), do: "v=#{x}!"
end|) =~ ~S|"v=${x}!"|
    end

    test "atom-keyed map literal → Rian %{k: v}" do
      assert rian("defmodule M do\n  def m, do: %{lo: 1, hi: 2}\nend") =~ "%{lo: 1, hi: 2}"
    end

    test "a call to a sibling Rian module is emitted inline, not flagged" do
      out = rian("defmodule M do\n  def g(x), do: Core.from_expr(x)\nend")
      assert out =~ "pub def g(x _Ty) _Ret := Core.from_expr(x)"
      refute out =~ "remote/stdlib call: Core"
    end
  end

  describe "struct/map updates don't crash the total walk" do
    test "struct update `%M{base | f: v}` is flagged, not a FunctionClauseError" do
      out = rian("defmodule M do\n  def u(p), do: %P{p | type: p.t}\nend")
      assert out =~ ~s|TODO_PORT("struct update|
    end

    test "map update `%{base | k: v}` is flagged too" do
      out = rian("defmodule M do\n  def u(m), do: %{m | k: 1}\nend")
      assert out =~ "TODO_PORT"
    end
  end

  describe "stdlib auto-mapping (A1)" do
    test "Map.get/put map to Dict.* and stop being markers" do
      out = rian("defmodule M do\n  def f(m, k), do: Map.put(m, k, 1)\nend")
      assert out =~ "Dict.put(m, k, 1)"
      refute out =~ ~s|TODO_PORT("remote/stdlib call: Map.put|
    end

    test "Map.get is arity-sensitive: /2 → Dict.get, /3 → Dict.get_or" do
      g2 = rian("defmodule M do\n  def f(m, k), do: Map.get(m, k)\nend")
      g3 = rian("defmodule M do\n  def f(m, k), do: Map.get(m, k, 0)\nend")
      assert g2 =~ "Dict.get(m, k)"
      assert g3 =~ "Dict.get_or(m, k, 0)"
    end

    test "Enum.sum → List.sum" do
      assert rian("defmodule M do\n  def f(xs), do: Enum.sum(xs)\nend") =~ "List.sum(xs)"
    end

    test "honesty: an unmapped call stays a marker, never a phantom List.map" do
      out = rian("defmodule M do\n  def f(xs), do: Enum.map(xs, fn x -> x end)\nend")
      assert out =~ ~s|TODO_PORT("remote/stdlib call: Enum.map|
      refute out =~ "List.map"
    end

    test "stats counts auto-mapped calls" do
      {_t, stats} =
        Transpile.transpile_with_stats("defmodule M do\n  def f(m, k), do: Map.put(m, k, 1)\nend")

      assert stats.mapped == 1
    end
  end

  describe "rank/1 — folder-mode port-difficulty triage" do
    test "sorts easiest-first by markers/def and tags difficulty" do
      rows =
        Transpile.rank([
          {"hard.ex", %{defs: 2, ports: 14}},
          {"easy.ex", %{defs: 5, ports: 5}},
          {"med.ex", %{defs: 4, ports: 16}}
        ])

      assert Enum.map(rows, & &1.name) == ["easy.ex", "med.ex", "hard.ex"]
      assert Enum.map(rows, & &1.tag) == ["easy", "med", "hard"]
    end

    test "a module with no def groups is tagged `—`" do
      assert [%{tag: "—"}] = Transpile.rank([{"x.ex", %{defs: 0, ports: 3}}])
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

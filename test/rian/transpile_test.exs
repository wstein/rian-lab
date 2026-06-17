defmodule Rian.TranspileTest do
  use ExUnit.Case, async: true

  alias Rian.Transpile

  defp rian(src), do: Transpile.transpile(src)

  describe "defstruct → a Rian `struct` record (named for the module)" do
    test "an atom-list defstruct becomes `struct Mod(field _Unk, …)`" do
      out = rian("defmodule Point do\n  defstruct [:x, :y]\nend")
      assert out =~ "struct Point(x _Unk, y _Unk)"
      refute out =~ "TODO[port]: defstruct"
    end

    test "keyword defaults port the names; defaults are dropped (human types them)" do
      out = rian("defmodule Cfg do\n  defstruct host: \"localhost\", port: 0\nend")
      assert out =~ "struct Cfg(host _Unk, port _Unk)"
    end

    test "a dynamic defstruct (non-literal) falls back to a marker, not a wrong decl" do
      out = rian("defmodule D do\n  @fields [:a]\n  defstruct @fields\nend")
      assert out =~ "# TODO[port]: defstruct @fields"
    end

    test "nested struct modules (the `ir.ex` shape) flatten to `struct` decls" do
      src = """
      defmodule IR do
        defmodule Field do
          @enforce_keys [:type]
          defstruct [:label, :type]
        end

        defmodule Variant do
          defstruct ctor: nil, fields: []
        end
      end
      """

      out = rian(src)
      assert out =~ "mod IR do"
      assert out =~ "struct Field(label _Unk, type _Unk)"
      assert out =~ "struct Variant(ctor _Unk, fields _Unk)"
      # the wrapper `defmodule`s and `@enforce_keys` are absorbed, not left as markers
      refute out =~ "TODO[port]: defmodule"
      refute out =~ "enforce_keys"
    end

    test "a nested module with functions nests as `mod`, not flattened" do
      src = "defmodule Outer do\n  defmodule Helper do\n    def h(x), do: x\n  end\nend"
      out = rian(src)
      assert out =~ "mod Helper do"
      assert out =~ "def h("
    end
  end

  describe "@rian attribute annotations — author the type inference can't recover" do
    test "a `@rian` def attribute supplies the signature (no --infer needed)" do
      src = ~S'''
      defmodule M do
        use Rian.Ann
        @rian "pub def rust_param(Symbol, String) String"
        def rust_param(name, val), do: val
      end
      '''

      out = rian(src)
      assert out =~ "pub def rust_param(name Symbol, val String) String := val"
      # the @rian attribute + use Rian.Ann are consumed, not re-emitted as markers
      refute out =~ "TODO[port]: @rian"
      refute out =~ "use Rian.Ann"
    end

    test "an annotation overrides what inference would otherwise hole/guess" do
      src = ~S'''
      defmodule M do
        use Rian.Ann
        @rian "def tag(Symbol) Bool"
        defp tag(x), do: process(x)
      end
      '''

      assert Transpile.transpile(src, infer: true) =~ "def tag(x Symbol) Bool := process(x)"
    end

    test "an unparseable @rian annotation is warned about, not silently dropped" do
      src = ~S'''
      defmodule M do
        use Rian.Ann
        @rian "pub? not valid rian"
        def f(x), do: x
      end
      '''

      warning = ExUnit.CaptureIO.capture_io(:stderr, fn -> rian(src) end)
      assert warning =~ "unparseable @rian annotation"
    end

    test "a `@rian` struct attribute supplies the field types (heredoc multiline)" do
      src = ~S'''
      defmodule Func do
        use Rian.Ann
        @rian """
        struct Func(name String, params Vec(Param),
                    ret String, is_pub Bool)
        """
        defstruct [:name, :params, :ret, :pub?]
      end
      '''

      assert rian(src) =~ "struct Func(name String, params Vec(Param), ret String, is_pub Bool)"
      # the annotation OVERRODE the holes — no `_Unk` field in the struct decl
      refute rian(src) =~ ~r/struct Func\([^)]*_Unk/
    end

    test "a `@rian` type attribute emits the type DEFINITION (at its central home)" do
      # the type is defined ONCE, where it lives (e.g. the IR module).
      src = ~S'''
      defmodule IR do
        use Rian.Ann
        @rian "type Expr := ENum | ECall | EIf"
      end
      '''

      assert rian(src) =~ "type Expr := ENum | ECall | EIf"
    end

    test "a def annotation REFERENCES a type by name — no per-use redefinition" do
      # `Expr` is defined centrally (above); a *using* module just refers to it.
      src = ~S'''
      defmodule M do
        use Rian.Ann
        @rian "pub def f(x Expr) Int53"
        def f(x), do: g(x)
      end
      '''

      out = rian(src)
      assert out =~ "pub def f(x Expr) Int53"
      # the using module does NOT redeclare `type Expr` — it only refers to the name
      refute out =~ "type Expr"
    end

    test "an annotation whose head matches no def is ignored (typo-safe)" do
      src = ~S'''
      defmodule M do
        use Rian.Ann
        @rian "pub def wrong_name(Int53) Int53"
        def f(x), do: x + 1
      end
      '''

      out = Transpile.transpile(src, infer: true)
      assert out =~ "pub def f(x Int53) Int53 := x + 1"
      refute out =~ "wrong_name"
    end

    test "no annotation → unchanged behaviour" do
      assert rian("defmodule M do\n  def f(x), do: x\nend") =~ "pub def f(x _Unk) _Unk := x"
    end
  end

  describe "structure that has a clear Rian image" do
    test "module + simple def → `mod`/`pub def` with type holes" do
      out = rian("defmodule M do\n  def double(x), do: x + x\nend")
      assert out =~ "mod M do"
      assert out =~ "pub def double(x _Unk) _Unk := x + x"
    end

    test "defp is private (`def`, no `pub`) and OMITS the return (infer-local, ADR-0034)" do
      # a private function needn't declare its return — `Rian.InferLocal` recovers it.
      out = rian("defmodule M do\n  defp f(x), do: x\nend")
      assert out =~ ~r/\n  def f\(x _Unk\) :=/
      refute out =~ "def f(x _Unk) _Unk"
    end

    test "a `pub def` (from Elixir `def`) KEEPS its return hole (declare-public)" do
      out = rian("defmodule M do\n  def f(x), do: x\nend")
      assert out =~ "pub def f(x _Unk) _Unk := x"
    end

    test "omitting the private return drops one hole per defp" do
      {_pub, ps} =
        {nil, Rian.Transpile.transpile_with_stats("defmodule M do\n  def f(x), do: x\nend")}

      {_priv, qs} =
        {nil, Rian.Transpile.transpile_with_stats("defmodule M do\n  defp f(x), do: x\nend")}

      # public f has 2 holes (param + return); private f has 1 (param only).
      assert elem(ps, 1).holes == 2
      assert elem(qs, 1).holes == 1
    end

    test "multi-clause def emits one sig + per-clause bodies" do
      out = rian("defmodule M do\n  def f(0), do: :z\n  def f(n), do: n\nend")
      assert out =~ "pub def f(_Unk) _Unk"
      assert out =~ "pub def f(0) := :z"
      assert out =~ "pub def f(n) := n"
    end

    test "case with a ctor/struct pattern arm" do
      out =
        rian("""
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
    test "an unmapped stdlib call (no Rian image) stays a greppable marker" do
      out = rian("defmodule M do\n  def t(s), do: String.split(s, \",\")\nend")
      assert out =~ "TODO_PORT(\"remote/stdlib call: String.split"
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

    test "multi-statement body → Rian `;`-separated block with binds" do
      out = rian("defmodule M do\n  def g(x) do\n    y = x + 1\n    z = y + 1\n    z\n  end\nend")
      assert out =~ "y := x + 1; z := y + 1; z"
    end

    test "a call to a sibling Rian module is emitted inline, not flagged" do
      out = rian("defmodule M do\n  def g(x), do: Core.from_expr(x)\nend")
      assert out =~ "pub def g(x _Unk) _Unk := Core.from_expr(x)"
      refute out =~ "remote/stdlib call: Core"
    end

    test "the pipe `|>` renders infix, not as the prefix call `|>(l, r)`" do
      out = rian("defmodule M do\n  def g(xs), do: xs |> foo() |> bar()\nend")
      assert out =~ "xs |> foo() |> bar()"
      refute out =~ "|>("
    end

    test "a stdlib call mapped inside a pipe accounts for the injected first arg" do
      out = rian("defmodule M do\n  def g(xs), do: xs |> Enum.reverse()\nend")
      assert out =~ "xs |> List.reverse()"
      refute out =~ "remote/stdlib call"
    end

    test "a multi-clause `fn` lowers to a single-clause lambda over a `case`" do
      out =
        rian(
          "defmodule M do\n  def g(xs), do: Enum.reduce(xs, 0, fn 0, a -> a; x, a -> x + a end)\nend"
        )

      assert out =~ "(p1, p2) -> case {p1, p2} do"
      assert out =~ "{0, a} -> a"
      assert out =~ "{x, a} -> x + a"
      refute out =~ "multi-clause fn"
    end

    test "a bare map *pattern* key renders without a stray colon (`%{k: p}` not `%{:k: p}`)" do
      out = rian("defmodule M do\n  def g(%{lo: a}), do: a\nend")
      assert out =~ "%{lo: a}"
      refute out =~ "%{:lo"
    end

    test "a match `=` in expression position renders as `:=`, not the prefix `=(l, r)`" do
      out = rian("defmodule M do\n  def g(x), do: with(y = f(x), do: y)\nend")
      assert out =~ "y := f(x)"
      refute out =~ "=(y"
    end
  end

  describe "Elixir module attributes" do
    test "a referenced value-attribute lowers to a `const`; references read the bare name" do
      out =
        rian("defmodule M do\n  @prims ~w(a b c)\n  def names, do: @prims\nend")

      assert out =~ ~s|const prims _Unk := ["a", "b", "c"]|
      assert out =~ "pub def names() _Unk := prims"
      # the reference is the bare const name, never the unlexable `@(prims)`
      refute out =~ "@(prims"
    end

    test "the `a` modifier of `~w` yields an atom list" do
      assert rian("defmodule M do\n  @ks ~w(a b)a\n  def k, do: @ks\nend") =~
               "const ks _Unk := [:a, :b]"
    end

    test "a directive attribute (`@impl`, unreferenced) stays a marker, not a `const`" do
      out = rian("defmodule M do\n  @impl true\n  def c(x), do: x\nend")
      assert out =~ "# TODO[port]: @impl true"
      refute out =~ "const impl"
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

    test "Enum.map → List.map with its lambda eta-translated" do
      out = rian("defmodule M do\n  def f(xs), do: Enum.map(xs, &(&1 + 1))\nend")
      assert out =~ "List.map(xs, (p1) -> p1 + 1)"
    end

    test "honesty: a stdlib call with NO Rian image stays a marker, never faked" do
      out = rian("defmodule M do\n  def f(s), do: MapSet.new(s)\nend")
      assert out =~ ~s|TODO_PORT("remote/stdlib call: MapSet.new|
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

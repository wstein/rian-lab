defmodule Rian.TranspileInferTest do
  use ExUnit.Case, async: true

  alias Rian.Transpile
  alias Rian.Transpile.Infer

  # transpile WITH inference and return the rendered lines (header stripped).
  defp infer(body) do
    "defmodule M do\n#{body}\nend"
    |> Transpile.transpile(infer: true)
    |> String.split("\n")
  end

  defp sig(body, name), do: Enum.find(infer(body), &String.contains?(&1, "def #{name}("))

  describe "monomorphic inference from usage" do
    test "arithmetic pins Int53 (the cross-target default), param + return" do
      assert sig("  def f(x), do: x + 1", "f") == "  pub def f(x Int53) Int53 := x + 1"
    end

    test "string concat pins String" do
      assert sig("  def g(s), do: s <> \"!\"", "g") ==
               "  pub def g(s String) String := s <> \"!\""
    end

    test "if condition is Bool, branches join to Int53" do
      assert sig("  def p(b), do: if b, do: 1, else: 2", "p") =~ "pub def p(b Bool) Int53 :="
    end

    test "list cons pattern + element use → Vec(Int53)" do
      out = sig("  def s([]), do: 0\n  def s([h | t]), do: h + s(t)", "s")
      assert out =~ "Vec(Int53)"
    end
  end

  describe "prelude-call propagation" do
    test "Enum.map with a lambda → Vec(Int53) param and return" do
      assert sig("  def m(xs), do: Enum.map(xs, fn x -> x + 1 end)", "m") ==
               "  pub def m(xs Vec(Int53)) Vec(Int53) := List.map(xs, (x) -> x + 1)"
    end

    test "captures eta-expand and still type" do
      assert sig("  def m(xs), do: Enum.map(xs, &(&1 + 1))", "m") =~ "Vec(Int53)"
    end
  end

  describe "Int53 cross-target rule" do
    test "numeric holes never resolve to Int64 or Int (off :js/:rs/:jvm)" do
      lines = infer("  def a(x), do: x * 2\n  def b(n), do: n - 1\n  def c(y), do: y + y")
      txt = Enum.join(lines, "\n")
      assert txt =~ "Int53"
      refute txt =~ "Int64"
      refute txt =~ ~r/\bInt\b(?!5)/
    end
  end

  describe "polymorphism (honest, partial)" do
    test "identity generalizes to forall T" do
      assert sig("  def id(x), do: x", "id") == "  pub def id(x T) T forall T := x"
    end
  end

  describe "intra-module sibling propagation (two-pass)" do
    test "a caller adopts a local helper's inferred return type" do
      # double/1 infers Int53; use/1 calls it, so its return adopts Int53.
      out = sig("  def double(x), do: x + x\n  def use(n), do: double(n)", "use")
      assert out =~ "Int53"
    end
  end

  describe "Phase B — Result/error-set inference (`{:ok,_}`/`{:error,Tag}`)" do
    test "synthesizes the error set and types the function as `Payload | Errors`" do
      src = """
      defmodule Math do
        def checked_div(a, b) do
          case b do
            0 -> {:error, DivByZero}
            _ -> {:ok, div(a, b)}
          end
        end
      end
      """

      out = Transpile.transpile(src, infer: true)
      assert out =~ "type Errors := DivByZero"
      assert out =~ "pub def checked_div(a Int53, b Int53) Int53 | Errors :="
    end

    test "the inferred Result draft type-checks (accident-free)" do
      src = """
      defmodule Math do
        def checked_div(a, b) do
          case b do
            0 -> {:error, DivByZero}
            _ -> {:ok, div(a, b)}
          end
        end
      end
      """

      body =
        Transpile.transpile(src, infer: true)
        |> String.split("\n")
        |> Enum.reject(&String.starts_with?(&1, "#"))
        |> Enum.join("\n")

      assert {:ok, _} = safe_compile(body)
    end

    test "honesty: conflicting `{:ok, _}` payload types leave a hole, not a guess" do
      src = """
      defmodule M do
        def f(x) do
          case x do
            0 -> {:ok, 1}
            1 -> {:ok, "s"}
            _ -> {:error, Bad}
          end
        end
      end
      """

      out = Transpile.transpile(src, infer: true)
      refute out =~ "| Errors"
      assert out =~ "def f(x Int53) _Unk"
    end

    test "honesty: a non-Capitalized error tag (Elixir idiom) is NOT made a Result" do
      # {:error, :atom} / {:error, "msg"} can't be a synthesized variant → leave holes.
      out =
        Transpile.transpile("defmodule M do\n  def f(x), do: {:error, :nope}\nend", infer: true)

      refute out =~ "Errors"
      assert out =~ "_Unk"
    end
  end

  describe "Phase A — whole-program cross-module signatures" do
    test "a cross-module call adopts the callee's inferred signature" do
      a = "defmodule A do\n  def foo(x), do: x + 1\nend"
      b = "defmodule B do\n  def bar(y), do: A.foo(y)\nend"
      Transpile.prime_xmod([a, b])

      try do
        line =
          Transpile.transpile(b, infer: true)
          |> String.split("\n")
          |> Enum.find(&String.contains?(&1, "def bar"))

        assert line == "  pub def bar(y Int53) Int53 := A.foo(y)"
      after
        Rian.Transpile.Infer.clear_xmod()
      end
    end
  end

  describe "honesty — leave a hole when nothing pins it" do
    test "an unknown callee leaves _Unk" do
      assert sig("  def h(x), do: unknown_fn(x)", "h") ==
               "  pub def h(x _Unk) _Unk := unknown_fn(x)"
    end

    test "a tuple return is left a hole in the MVP" do
      assert sig("  def t(x), do: {:ok, x}", "t") =~ "_Unk"
    end

    test "infer_report names the remaining holes with reasons" do
      report = Transpile.infer_report("defmodule M do\n  def t(x), do: Tuple.to_list(x)\nend")
      assert {{"t", 1}, ledger} = List.keyfind(report, {"t", 1}, 0)
      assert {"ret", :unresolved} in ledger
    end
  end

  describe "end-to-end — an inferred draft type-checks" do
    test "the filled signatures parse and pass Rian.Decl.compile" do
      body =
        infer("  def double(x), do: x + x\n  def neg(x), do: -x\n  def id(x), do: x")
        |> Enum.reject(&String.starts_with?(&1, "#"))
        |> Enum.join("\n")

      assert {:ok, _} = safe_compile(body)
    end
  end

  describe "inference is off by default (existing behavior preserved)" do
    test "without :infer, holes remain _Unk" do
      out = Transpile.transpile("defmodule M do\n  def f(x), do: x + 1\nend")
      assert out =~ "pub def f(x _Unk) _Unk := x + 1"
    end
  end

  describe "module-less sources infer just like a module body (ADR-0075)" do
    test "a bare `def` fills its holes from usage" do
      out = Transpile.transpile("def double(n) do\n  n * 2\nend", infer: true)
      assert out =~ "pub def double(n Int53) Int53 := n * 2"
    end

    test "multi-clause bare defs get one inferred signature" do
      src =
        "def sign(0) do\n  0\nend\n\ndef sign(n) when n > 0 do\n  1\nend\n\ndef sign(_) do\n  -1\nend"

      out = Transpile.transpile(src, infer: true)
      assert out =~ "pub def sign(Int53) Int53"
    end

    test "infer_report works on a module-less source" do
      report = Transpile.infer_report("def t(x) do\n  Tuple.to_list(x)\nend")
      assert {{"t", 1}, ledger} = List.keyfind(report, {"t", 1}, 0)
      assert {"ret", :unresolved} in ledger
    end
  end

  describe "triage stats are header-honest (no phantom markers, defs at any indent)" do
    test "a clean module-less draft reports zero markers and counts its defs" do
      {_, stats} = Transpile.transpile_with_stats("def double(n) do\n  n * 2\nend", infer: true)
      assert stats.ports == 0
      assert stats.defs == 1
    end

    test "a clean `defmodule` draft also reports zero markers (header not self-counted)" do
      {_, stats} =
        Transpile.transpile_with_stats("defmodule M do\n  def f(x), do: x + 1\nend", infer: true)

      assert stats.ports == 0
    end
  end

  describe "`@spec` harvesting — declared types seed inference, cross-checked (ADR-0075)" do
    test "a String.t() spec fills the param and return holes" do
      body = "  @spec greet(String.t()) :: String.t()\n  def greet(name), do: name"
      assert sig(body, "greet") == "  pub def greet(name String) String := name"
    end

    test "a list spec fills Vec(_) — [String.t()] -> Vec(String)" do
      body = "  @spec names([String.t()]) :: integer()\n  def names(xs), do: xs"
      assert sig(body, "names") =~ "pub def names(xs Vec(String))"
    end

    test "boolean primitive translates" do
      body = "  @spec ok?(boolean()) :: boolean()\n  def ok?(b), do: b"
      assert sig(body, "ok?") =~ "pub def ok?(b Bool) Bool"
    end

    test "float primitive translates" do
      body = "  @spec half(float()) :: float()\n  def half(x), do: x"
      assert sig(body, "half") =~ "pub def half(x Float64) Float64"
    end

    test "any()/term() carries no concrete type -> no hint (slot left to inference)" do
      # `any()` gives no hint; the body here is identity, so inference generalizes the
      # unpinned slot to a tvar — a human still owns any genuinely-open type.
      body = "  @spec wrap(any()) :: any()\n  def wrap(x), do: x"
      assert sig(body, "wrap") =~ "forall T"
    end

    test "an untranslatable any() return leaves a _Unk hole, not a guess" do
      body = "  @spec opaque(integer()) :: any()\n  def opaque(n), do: Tuple.to_list(n)"
      assert sig(body, "opaque") =~ "_Unk"
    end

    test "a proven body type WINS over a contradictory spec (the cross-check)" do
      # body concatenates -> String; the bogus `integer()` spec is dropped, not adopted.
      body = "  @spec shout(integer()) :: integer()\n  def shout(s), do: s <> \"!\""
      assert sig(body, "shout") == "  pub def shout(s String) String := s <> \"!\""
    end

    test "an untranslatable spec (tuple return) leaves the body inference untouched" do
      # {:ok, _} has no clean Rian image -> no hint; the param is still spec-filled.
      body = "  @spec find(String.t()) :: {:ok, integer()}\n  def find(k), do: k"
      assert sig(body, "find") =~ "pub def find(k String)"
    end

    test "a spec-less function is unaffected (generic inference still applies)" do
      body = "  def mystery(z), do: z"
      assert sig(body, "mystery") =~ "forall T"
    end

    test "the consumed @spec becomes passive provenance, not a TODO[port] action marker" do
      out = infer("  @spec greet(String.t()) :: String.t()\n  def greet(name), do: name")
      assert Enum.any?(out, &(&1 =~ "# spec: @spec greet"))
      refute Enum.any?(out, &(&1 =~ "TODO[port]: @spec"))
    end

    test "off by default: without :infer, specs are not harvested (holes remain)" do
      out =
        Transpile.transpile(
          "defmodule M do\n  @spec g(String.t()) :: String.t()\n  def g(s), do: s\nend"
        )

      assert out =~ "pub def g(s _Unk) _Unk := s"
      # but the spec is still surfaced as provenance, never lost
      assert out =~ "# spec: @spec g"
    end

    test "a spec-filled draft compiles (the fill is real, well-formed Rian)" do
      body = "  @spec greet(String.t()) :: String.t()\n  def greet(name), do: name"
      assert {:ok, :compiled} = safe_compile("mod M do\n#{sig(body, "greet")}\nend")
    end
  end

  describe "`@type` harvesting — synthesize type decls + resolve local refs (ADR-0075)" do
    test "@type t :: %__MODULE__{} resolves t() refs to the module's struct" do
      src = """
      defmodule Box do
        defstruct [:v]
        @type t :: %__MODULE__{}
        @spec unwrap(t()) :: t()
        def unwrap(b), do: b
      end
      """

      out = Transpile.transpile(src, infer: true)
      assert out =~ "pub def unwrap(b Box) Box := b"
    end

    test "a union @type synthesizes `type Name := …` AND resolves refs to the name" do
      src = """
      defmodule M do
        @type ty :: String.t() | atom()
        @spec norm(ty()) :: ty()
        def norm(x), do: x
      end
      """

      out = Transpile.transpile(src, infer: true)
      assert out =~ "type Ty := String | Symbol"
      assert out =~ "pub def norm(x Ty) Ty := x"
    end

    test "a single-type @type alias inlines (no decl) — module() → Symbol" do
      src = """
      defmodule M do
        @type modname :: module()
        @spec load(modname()) :: integer()
        def load(m), do: m
      end
      """

      out = Transpile.transpile(src, infer: true)
      refute out =~ "type Modname"
      assert out =~ "pub def load(m Symbol)"
    end

    test "a remote @type alias resolves to the module name — Session.t() → Session" do
      src = """
      defmodule M do
        @type t :: Session.t()
        @spec cur(t()) :: t()
        def cur(s), do: s
      end
      """

      assert Transpile.transpile(src, infer: true) =~ "pub def cur(s Session) Session := s"
    end

    test "an untranslatable @type (tuple) yields no resolution — no decl, no spec fill" do
      src = """
      defmodule M do
        @type pair :: {integer(), integer()}
        @spec mk(pair()) :: pair()
        def mk(p), do: p
      end
      """

      out = Transpile.transpile(src, infer: true)
      # no synthesized decl (untranslatable), and the tuple ref gives no hint
      refute out =~ "type Pair :="
      assert out =~ "# type: @type pair"
      # the spec adds nothing, so identity inference still generalizes (not a wrong fill)
      assert out =~ "pub def mk(p T) T forall T := p"
    end

    test "a synthesized union-type draft compiles (the decl + its use are valid Rian)" do
      src = """
      defmodule M do
        @type ty :: String.t() | atom()
        @spec norm(ty()) :: ty()
        def norm(x), do: x
      end
      """

      body =
        Transpile.transpile(src, infer: true)
        |> String.split("\n")
        |> Enum.reject(&String.starts_with?(String.trim_leading(&1), "#"))
        |> Enum.join("\n")

      assert {:ok, :compiled} = safe_compile(body)
    end
  end

  describe "spec_type_to_rian/2 — render an Elixir @spec type as a Rian type string" do
    defp rian_t(spec_str) do
      {:ok, {:"::", _, [_, ret]}} = Code.string_to_quoted("#{spec_str}")
      Rian.Transpile.Infer.spec_type_to_rian(ret)
    end

    test "clean Elixir types map to Rian" do
      assert rian_t("f() :: integer()") == "Int53"
      assert rian_t("f() :: String.t()") == "String"
      assert rian_t("f() :: [String.t()]") == "Vec(String)"
      assert rian_t("f() :: boolean()") == "Bool"
    end

    test "an Elixir type with no clean Rian image renders `_Unk`" do
      assert rian_t("f() :: {:ok, integer()}") == "_Unk"
      assert rian_t("f() :: map()") == "_Unk"
    end
  end

  describe "struct vocabulary in inference — Lever B" do
    test "struct construction types the return to the struct" do
      assert sig("  def mk(n), do: %ENum{text: n}", "mk") =~ ~r/\) ENum :=/
    end

    test "a single-struct case-arm pattern types the scrutinee" do
      out =
        sig(
          "  def t(x) do\n    case x do\n      %ENum{text: v} -> v\n      _ -> 0\n    end\n  end",
          "t"
        )

      assert out =~ "def t(x ENum)"
    end

    test "a struct clause-head pattern types the parameter" do
      assert sig("  def text(%ENum{text: t}), do: t", "text") =~ "def text(ENum)"
    end
  end

  describe "guard, type-predicate, and Kernel-accessor evidence (Phase B)" do
    # `gg(...)` is an unknown call, so the guard/body BIF is the ONLY type evidence.
    # A guarded clause renders a type-only signature header (`pub def f(String) _Unk`),
    # the param name living on the clause line below it.
    test "is_binary guard → String" do
      assert sig("  def f(s) when is_binary(s), do: gg(s)", "f") =~ "f(String)"
    end

    test "is_integer guard → Int53 (the portable default)" do
      assert sig("  def f(n) when is_integer(n), do: gg(n)", "f") =~ "f(Int53)"
    end

    test "is_atom guard → Symbol" do
      assert sig("  def f(a) when is_atom(a), do: gg(a)", "f") =~ "f(Symbol)"
    end

    test "a comparison guard pins the operand numeric (Int53)" do
      assert sig("  def f(x) when x > 0, do: gg(x)", "f") =~ "f(Int53)"
    end

    test "a type-predicate in a body (not just a guard) is evidence too" do
      assert sig("  def f(x), do: if(is_integer(x), do: gg(x), else: gg(x))", "f") =~ "f(x Int53)"
    end

    test "byte_size(arg) → String param, Int53 return" do
      assert sig("  def f(s), do: byte_size(s)", "f") ==
               "  pub def f(s String) Int53 := byte_size(s)"
    end

    test "length(arg) → Int53 return (the list element stays open)" do
      assert sig("  def f(xs), do: length(xs)", "f") =~ ") Int53 := length(xs)"
    end

    test "a predicate without a clean single Rian type is NOT over-claimed (stays `_Unk`)" do
      # `is_tuple`/`is_map`/`is_struct` have no single Rian signature type, so we
      # deliberately do not map them — the param stays an honest hole rather than a
      # guessed (and likely wrong) concrete type.
      assert sig("  def f(t) when is_tuple(t), do: gg(t)", "f") =~ "f(_Unk)"
      assert sig("  def f(m) when is_map(m), do: gg(m)", "f") =~ "f(_Unk)"
    end
  end

  describe "constraint generation — literals & operators" do
    test "a float literal pins Float64 through arithmetic" do
      assert sig("  def f(x), do: x + 1.0", "f") == "  pub def f(x Float64) Float64 := x + 1.0"
    end

    test "a bare string / bool literal pins its return type" do
      assert sig(~s|  def f(), do: "hi"|, "f") == ~s|  pub def f() String := "hi"|
      assert sig("  def f(), do: true", "f") == "  pub def f() Bool := true"
    end

    test "a `nil` literal is Option-shaped" do
      assert sig("  def f(), do: nil", "f") =~ "None"
    end

    test "string interpolation is String regardless of the hole's type" do
      assert sig(~S|  def f(s), do: "v=#{s}"|, "f") =~ ") String :="
    end

    test "`/` is Float64 division (operands left open)" do
      assert sig("  def f(a, b), do: a / b", "f") =~ ") Float64 := a / b"
    end

    test "list concat `++` pins both operands and the result to a Vec" do
      assert sig("  def f(a, b), do: a ++ b", "f") =~ "f(a Vec(T), b Vec(T)) Vec(T) forall T"
    end

    test "`and` pins both operands and the result to Bool" do
      assert sig("  def f(a, b), do: a and b", "f") ==
               "  pub def f(a Bool, b Bool) Bool := a and b"
    end

    test "an `if` with no `else` is an open hole in value position" do
      assert sig("  def f(c), do: if(c, do: 1)", "f") =~ "f(c Bool) _Unk :="
    end
  end

  describe "constraint generation — Kernel accessors & predicate evidence" do
    test "is_float / is_boolean / is_list guards type the param" do
      assert sig("  def f(x) when is_float(x), do: x", "f") =~ "f(Float64)"
      assert sig("  def f(x) when is_boolean(x), do: x", "f") =~ "f(Bool)"
      assert sig("  def f(x) when is_list(x), do: x", "f") =~ "f(Vec(T)) Vec(T) forall T"
    end

    test "hd / tl decompose a Vec" do
      assert sig("  def f(xs), do: hd(xs)", "f") == "  pub def f(xs Vec(T)) T forall T := hd(xs)"
      assert sig("  def f(xs), do: tl(xs)", "f") =~ "f(xs Vec(T)) Vec(T) forall T := tl(xs)"
    end
  end

  describe "constraint generation — captures, lists, structs" do
    test "an eta-expanded `&(&1 + &2)` infers a binary Fn" do
      assert sig("  def f(), do: &(&1 + &2)", "f") =~ "Fn(Int53, Int53, Int53)"
    end

    test "a `&name/arity` capture is a Fn of that arity" do
      assert sig("  def f(), do: &g/2", "f") =~ "(p1, p2) -> g(p1, p2)"
    end

    test "a list literal pins Vec(Int53); a cons body threads the element type" do
      assert sig("  def f(), do: [1, 2, 3]", "f") == "  pub def f() Vec(Int53) := [1, 2, 3]"
      assert sig("  def f(h, t), do: [h | t]", "f") =~ "f(h T, t Vec(T)) Vec(T) forall T"
    end

    test "a struct construction / pattern carries the struct's nominal type" do
      assert sig("  def f(%Point{x: a}), do: a", "f") =~ "f(Point)"
    end

    test "literal patterns (float / string / bool) pin the param" do
      assert sig("  def f([1.0]), do: 0", "f") =~ "f(Vec(Float64))"
      assert sig(~s|  def f("a"), do: 0|, "f") =~ "f(String)"
      assert sig("  def f(true), do: 0", "f") =~ "f(Bool)"
    end
  end

  describe "constraint generation — honest holes (conflict / unbound / occurs)" do
    test "a Bool↔String conflict leaves the proven type, never a wrong fill" do
      # `x` is the `if` condition (Bool) AND a `<>` operand (String): the conflict
      # is detected; the first-proven Bool stands rather than an accidental fill.
      assert sig(~s|  def f(x), do: if(x, do: x <> "y", else: "z")|, "f") =~ "f(x Bool)"
    end

    test "an unbound variable reference is an honest hole" do
      assert sig("  def f(), do: zzz", "f") == "  pub def f() _Unk := zzz"
    end

    test "a cyclic `[x | x]` is caught by the occurs-check and still types" do
      assert sig("  def f(x), do: [x | x]", "f") =~ "f(x T) Vec(T) forall T"
    end
  end

  describe "constraint generation — blocks, tuples, FFI, guarded arms" do
    test "a `false` literal and `not` pin Bool" do
      assert sig("  def f(), do: false", "f") == "  pub def f() Bool := false"
      assert sig("  def f(a), do: not a", "f") == "  pub def f(a Bool) Bool := not a"
    end

    test "a tuple pattern carries no constraint in the MVP (param stays a hole)" do
      assert sig("  def f({a, b}), do: a", "f") =~ "f(_Unk)"
    end

    test "a multi-statement block threads binds and non-bind statements to the last expr" do
      # `z = …` (a bind), then `z + 1` (a non-bind statement), then `z` (the value).
      assert sig("  def f(x) do\n    z = x + 1\n    z + 1\n    z\n  end", "f") =~
               "f(x Int53) Int53"
    end

    test "an atom-head FFI call (`:lists.reverse`) is an unmodelled hole" do
      assert sig("  def f(x), do: :lists.reverse(x)", "f") =~ "f(x _Unk) _Unk"
    end

    test "a guarded case arm is handled (tails recurse through the guard)" do
      assert sig("  def f(x), do: (case x do\n    n when n > 0 -> 1\n    _ -> 0\n  end)", "f") =~
               ") Int53 :="
    end

    test "Result analysis recurses into a block-bodied clause" do
      src = ~S'''
      defmodule M do
        def f(b) do
          x = b
          case x do
            0 -> {:error, Bad}
            _ -> {:ok, x}
          end
        end
      end
      '''

      # `b` is pinned Int53 by the `0` arm; the point is tails/1 walks the block body.
      assert Transpile.transpile(src, infer: true) =~ "def f(b Int53)"
    end
  end

  describe "collect_types/2 — list @type" do
    test "a `[t]` @type becomes a Vec term in the env" do
      assert Infer.collect_types([quote(do: @type(ids :: [integer()]))], "M") ==
               {%{ids: {:app, "Vec", [{:con, "Int53"}]}}, []}
    end
  end

  describe "spec_type_to_rian/2 — Elixir @spec AST → Rian type string" do
    test "primitive scalars map to their Rian image" do
      assert Infer.spec_type_to_rian(quote(do: integer())) == "Int53"
      assert Infer.spec_type_to_rian(quote(do: non_neg_integer())) == "Int53"
      assert Infer.spec_type_to_rian(quote(do: float())) == "Float64"
      assert Infer.spec_type_to_rian(quote(do: boolean())) == "Bool"
      assert Infer.spec_type_to_rian(quote(do: binary())) == "String"
      assert Infer.spec_type_to_rian(quote(do: atom())) == "Symbol"
      assert Infer.spec_type_to_rian(quote(do: String.t())) == "String"
    end

    test "lists become Vec, unions become `A | B`, structs their name" do
      assert Infer.spec_type_to_rian(quote(do: [integer()])) == "Vec(Int53)"
      assert Infer.spec_type_to_rian(quote(do: list(integer()))) == "Vec(Int53)"
      assert Infer.spec_type_to_rian(quote(do: integer() | float())) == "Int53 | Float64"
      assert Infer.spec_type_to_rian(quote(do: %Foo{})) == "Foo"
    end

    test "a bare atom literal is a Symbol" do
      assert Infer.spec_type_to_rian(:ok) == "Symbol"
    end

    test "types with no clean Rian image are an honest `_Unk` (never guessed)" do
      assert Infer.spec_type_to_rian(quote(do: any())) == "_Unk"
      assert Infer.spec_type_to_rian(quote(do: {integer(), atom()})) == "_Unk"
      assert Infer.spec_type_to_rian(quote(do: [tuple()])) == "_Unk"
      assert Infer.spec_type_to_rian(quote(do: integer() | {a, b})) == "_Unk"
    end

    test "a local @type ref resolves through the type_env" do
      assert Infer.spec_type_to_rian(quote(do: expr()), %{expr: {:con, "Expr"}}) == "Expr"
    end
  end

  describe "collect_specs/2" do
    test "harvests @spec params and return into a {name, arity} hint map" do
      assert Infer.collect_specs([quote(do: @spec(f(integer()) :: boolean()))]) ==
               %{{"f", 1} => %{params: [{:con, "Int53"}], ret: {:con, "Bool"}}}
    end

    test "a zero-arity spec has empty params" do
      assert Infer.collect_specs([quote(do: @spec(g() :: integer()))]) ==
               %{{"g", 0} => %{params: [], ret: {:con, "Int53"}}}
    end

    test "a `when`-bounded spec drops the quantifier (unresolved refs stay holes)" do
      assert Infer.collect_specs([quote(do: @spec(h(t) :: t when t: integer()))]) ==
               %{{"h", 1} => %{params: [nil], ret: nil}}
    end

    test "non-spec statements and non-list input yield no hints" do
      assert Infer.collect_specs([quote(do: def(notaspec(), do: 1))]) == %{}
      assert Infer.collect_specs(:not_a_list) == %{}
    end
  end

  describe "collect_types/2" do
    test "a union @type synthesizes a decl and a name binding" do
      assert Infer.collect_types([quote(do: @type(t :: integer() | float()))], "M") ==
               {%{t: {:con, "T"}}, ["type T := Int53 | Float64"]}
    end

    test "a single-type @type inlines (no decl)" do
      assert Infer.collect_types([quote(do: @type(id :: integer()))], "M") ==
               {%{id: {:con, "Int53"}}, []}
    end

    test "`%__MODULE__{}` resolves to the module, a remote `Mod.t()` to its name" do
      assert Infer.collect_types([quote(do: @type(me :: %__MODULE__{}))], "Mod") ==
               {%{me: {:con, "Mod"}}, []}

      assert Infer.collect_types([quote(do: @type(r :: Other.t()))], "M") ==
               {%{r: {:con, "Other"}}, []}
    end

    test "non-list input yields the empty env" do
      assert Infer.collect_types(:not_a_list, "M") == {%{}, []}
    end
  end

  defp safe_compile(src) do
    Rian.Decl.compile(src)
    {:ok, :compiled}
  rescue
    e -> {:error, Exception.message(e)}
  end
end

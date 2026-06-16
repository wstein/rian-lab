defmodule Rian.TranspileInferTest do
  use ExUnit.Case, async: true

  alias Rian.Transpile

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

  defp safe_compile(src) do
    Rian.Decl.compile(src)
    {:ok, :compiled}
  rescue
    e -> {:error, Exception.message(e)}
  end
end

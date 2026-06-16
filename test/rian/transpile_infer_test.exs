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
      assert out =~ "def f(x Int53) _Ret"
    end

    test "honesty: a non-Capitalized error tag (Elixir idiom) is NOT made a Result" do
      # {:error, :atom} / {:error, "msg"} can't be a synthesized variant → leave holes.
      out =
        Transpile.transpile("defmodule M do\n  def f(x), do: {:error, :nope}\nend", infer: true)

      refute out =~ "Errors"
      assert out =~ "_Ret"
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
    test "an unknown callee leaves _Ty/_Ret" do
      assert sig("  def h(x), do: unknown_fn(x)", "h") ==
               "  pub def h(x _Ty) _Ret := unknown_fn(x)"
    end

    test "a tuple return is left a hole in the MVP" do
      assert sig("  def t(x), do: {:ok, x}", "t") =~ "_Ret"
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
    test "without :infer, holes remain _Ty/_Ret" do
      out = Transpile.transpile("defmodule M do\n  def f(x), do: x + 1\nend")
      assert out =~ "pub def f(x _Ty) _Ret := x + 1"
    end
  end

  defp safe_compile(src) do
    Rian.Decl.compile(src)
    {:ok, :compiled}
  rescue
    e -> {:error, Exception.message(e)}
  end
end

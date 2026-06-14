defmodule Rian.InterpTest do
  # async: false — loads real modules into the VM via :code.load_binary.
  use ExUnit.Case, async: false

  alias Rian.{Beam, Decl, JS, Lower, Pratt, Reach}

  defp node_eval(js, expr) do
    case System.find_executable("node") do
      nil ->
        :no_node

      node ->
        path =
          Path.join(System.tmp_dir!(), "rian_interp_#{System.unique_integer([:positive])}.mjs")

        File.write!(path, js <> "\nconsole.log(String(#{expr}));\n")
        {out, 0} = System.cmd(node, [path])
        File.rm(path)
        String.trim(out)
    end
  end

  defp reach(src, fn_name) do
    src |> Decl.parse() |> Reach.analyze() |> Map.fetch!(fn_name)
  end

  describe "lexing & parsing `\\(expr)` holes (ADR-0069 §1)" do
    test "a string with no hole is a plain `{:str, _}`" do
      assert Pratt.parse(~S|"plain"|) == {:str, "plain"}
    end

    test "holes parse as embedded expressions; literal segments interleave" do
      assert Pratt.parse(~S|"a \(x) b \(y + 1)"|) ==
               {:str_interp,
                [
                  {:lit, "a "},
                  {:hole, {:id, "x"}},
                  {:lit, " b "},
                  {:hole, {:bin, "+", {:id, "y"}, {:num, "1"}}},
                  {:lit, ""}
                ]}
    end

    test "`\\\\(` is a literal backslash + paren, not a hole (escape-the-escape is free)" do
      assert Pratt.parse(~S|"esc \\(lit)"|) == {:str, "esc \\(lit)"}
    end

    test "an empty hole `\\()` is a parse error" do
      assert_raise ArgumentError, ~r/empty interpolation hole/, fn -> Pratt.parse(~S|"x \()"|) end
    end

    test "the detokenizer round-trips an interpolated string" do
      toks = Rian.Lexer.tokenize(~S|"n=\(n)!"|)
      assert Enum.any?(toks, &match?({:istr, _}, &1))
      assert Rian.Lexer.detokenize(toks) =~ ~S|"n=\(n)!"|
    end
  end

  describe "auto-stringify on the BEAM (ADR-0069 §2/§3)" do
    test "an Int53 hole stringifies via the native int→string" do
      {:ok, m} = Beam.load(~S|def greet(n Int53) String := "n is \(n)!"|, :interp_greet)
      assert m.greet(5) == "n is 5!"
      assert m.greet(-42) == "n is -42!"
    end

    test "multiple holes and an arithmetic hole concatenate left-to-right" do
      {:ok, m} =
        Beam.load(~S|def msg(a Int53, b Int53) String := "\(a) + \(b) = \(a + b)"|, :interp_msg)

      assert m.msg(2, 3) == "2 + 3 = 5"
    end

    test "a String hole is the identity (no stringify)" do
      {:ok, m} = Beam.load(~S|def hi(name String) String := "hi \(name)"|, :interp_hi)
      assert m.hi("ada") == "hi ada"
    end

    test "a Bool hole shows `true`/`false`" do
      {:ok, m} = Beam.load(~S|def flag(b Bool) String := "flag=\(b)"|, :interp_flag)
      assert m.flag(true) == "flag=true"
      assert m.flag(false) == "flag=false"
    end
  end

  describe "the same source lowers to JS and Rust (ADR-0069 §3 — portable, no FFI)" do
    @src ~S|def greet(n Int53) String := "n is \(n)!"|

    test "JS emits one flat `+` join (ADR-0069 §6) and runs under node" do
      js = JS.compile(@src)
      # single-shot join: a flat `+` chain over all parts, no nested cascade
      assert js =~ ~s|("n is " + String(n) + "!")|
      assert node_eval(js, "greet(5)") in [:no_node, "n is 5!"]
    end

    test "Rust lowers the join to a single `format!` (ADR-0069 §6)" do
      rs = Lower.to_rust(hd(Decl.parse(@src).funcs), [], %{})
      assert rs =~ ~s|format!("{}{}{}", "n is ", n.to_string(), "!")|
    end
  end

  describe "single-shot join-lowering (ADR-0069 §6)" do
    test "interpolation lowers to one `__prim_str_concat_all`, not a `<>` cascade" do
      assert {:call, {:id, "__prim_str_concat_all"}, parts} =
               Rian.Interp.resolve(
                 Pratt.parse(~S|"a \(x) b"|),
                 %{"x" => "String"},
                 %{}
               )

      # empty trailing literal dropped; flat list of parts, no nested `{:bin, "<>"}`
      assert parts == [{:str, "a "}, {:id, "x"}, {:str, " b"}]
    end

    test "the BEAM builds one binary; a multi-hole string runs correctly" do
      {:ok, m} =
        Beam.load(
          ~S|def m(a Int53, b Int53, c Int53) String := "\(a)-\(b)-\(c)"|,
          :interp_join_beam
        )

      assert m.m(1, 2, 3) == "1-2-3"
    end

    test "a single-part interpolation stays the bare value (no join prim)" do
      # `"\(name)"` (name : String) collapses to the identity — no concat at all
      assert Rian.Interp.resolve(Pratt.parse(~S|"\(name)"|), %{"name" => "String"}, %{}) ==
               {:id, "name"}
    end
  end

  describe "Reach is honest about interpolation (ADR-0069 §4)" do
    test "an Int53 hole keeps the function all-target (the portability win)" do
      assert reach(~S|def g(n Int53) String := "n=\(n)"|, "g").reach
             |> MapSet.to_list()
             |> Enum.sort() == [:ex, :js, :jvm, :rs]
    end

    test "an `Int` (arbitrary precision) hole inherits ADR-0064: off :rs/:jvm" do
      # `Int` reaches only [:ex, :js] (bignum gap on Rust/JVM), and interpolating
      # one inherits that — honestly, via the existing numeric blocker.
      assert reach(~S|def g(n Int) String := "n=\(n)"|, "g").reach
             |> MapSet.to_list()
             |> Enum.sort() == [:ex, :js]
    end
  end

  describe "un-stringifiable holes are a compile error, never a silent fallback (ADR-0035)" do
    test "a `Char` hole is rejected (ADR-0069 open item: dispatch-guard collision)" do
      assert_raise ArgumentError, ~r/`Char` is not supported yet/, fn ->
        Beam.load(~S|def f(c Char) String := "c=\(c)"|, :interp_char_err)
      end
    end

    test "a `Float` hole is rejected (ADR-0069 open item: round-trip divergence)" do
      assert_raise ArgumentError, ~r/`Float` is not supported yet/, fn ->
        Beam.load(~S|def f(x Float64) String := "x=\(x)"|, :interp_float_err)
      end
    end

    test "a hole whose type cannot be statically inferred is rejected" do
      assert_raise ArgumentError, ~r/no `Show` for|statically-known/, fn ->
        Beam.load(~S|def f(x Int64) String := "v=\(g(x))"|, :interp_unknown_err)
      end
    end
  end
end

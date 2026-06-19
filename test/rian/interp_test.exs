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
    # `Reach.entry/2` resolves the bare name against the `"name/arity"`-keyed report.
    src |> Decl.parse() |> Reach.analyze() |> Reach.entry(fn_name)
  end

  describe "lexing & parsing `${expr}` holes (ADR-0069 §1)" do
    test "a string with no hole is a plain `{:str, _}`" do
      assert Pratt.parse(~S|"plain"|) == {:str, "plain"}
    end

    test "a bare `$` not followed by `{` is an ordinary character" do
      assert Pratt.parse(~S|"$5.00"|) == {:str, "$5.00"}
    end

    test "holes parse as embedded expressions; literal segments interleave" do
      assert Pratt.parse(~S|"a ${x} b ${y + 1}"|) ==
               {:str_interp,
                [
                  {:lit, "a "},
                  {:hole, {:id, "x"}},
                  {:lit, " b "},
                  {:hole, {:bin, "+", {:id, "y"}, {:num, "1"}}},
                  {:lit, ""}
                ]}
    end

    test "a hole tracks brace depth, so a map/struct literal nests correctly" do
      assert Pratt.parse(~S|"m ${ {x} }"|) ==
               {:str_interp, [{:lit, "m "}, {:hole, {:tuple, [id: "x"]}}, {:lit, ""}]}
    end

    test "`\\$` writes a literal `$`, so `\\${` is a literal `${` (not a hole)" do
      assert Pratt.parse(~S|"price \${5}"|) == {:str, "price ${5}"}
    end

    test "an empty hole `${}` is a parse error" do
      assert_raise ArgumentError, ~r/empty interpolation hole/, fn -> Pratt.parse(~S|"x ${}"|) end
    end

    test "the detokenizer round-trips an interpolated string" do
      toks = Rian.Lexer.tokenize(~S|"n=${n}!"|)
      assert Enum.any?(toks, &match?({:istr, _}, &1))
      assert Rian.Lexer.detokenize(toks) =~ ~S|"n=${n}!"|
    end
  end

  describe "auto-stringify on the BEAM (ADR-0069 §2/§3)" do
    test "an Int53 hole stringifies via the native int→string" do
      {:ok, m} = Beam.load(~S|def greet(n Int53) String := "n is ${n}!"|, :interp_greet)
      assert m.greet(5) == "n is 5!"
      assert m.greet(-42) == "n is -42!"
    end

    test "multiple holes and an arithmetic hole concatenate left-to-right" do
      {:ok, m} =
        Beam.load(~S|def msg(a Int53, b Int53) String := "${a} + ${b} = ${a + b}"|, :interp_msg)

      assert m.msg(2, 3) == "2 + 3 = 5"
    end

    test "a String hole is the identity (no stringify)" do
      {:ok, m} = Beam.load(~S|def hi(name String) String := "hi ${name}"|, :interp_hi)
      assert m.hi("ada") == "hi ada"
    end

    test "a Bool hole shows `true`/`false`" do
      {:ok, m} = Beam.load(~S|def flag(b Bool) String := "flag=${b}"|, :interp_flag)
      assert m.flag(true) == "flag=true"
      assert m.flag(false) == "flag=false"
    end

    test "a `${call()}` hole stringifies via the callee's declared return type (ADR-0069)" do
      # the interpolation pass now has the scope's function signatures in scope, so a
      # call result resolves its type instead of erroring `no Show for unknown`.
      src = ~S"""
      def double(n Int53) Int53 := n * 2
      def label(s String) String := s
      def f() String := "got ${double(20)} / ${label("x")}"
      """

      {:ok, m} = Beam.load(src, :interp_call)
      assert m.f() == "got 40 / x"
    end

    test "a generic `${call()}` resolves the instantiated return (forall T)" do
      src = ~S"""
      def id(x T) T forall T := x
      def f() String := "id=${id(7)}"
      """

      {:ok, m} = Beam.load(src, :interp_generic_call)
      assert m.f() == "id=7"
    end

    test "a `${p.field}` field-access hole resolves to the field's declared type" do
      src = ~S"""
      type P := P(name String, age Int53)
      def greet(p P) String := "${p.name} is ${p.age}"
      """

      {:ok, m} = Beam.load(src, :interp_field)
      assert m.greet(%{__struct__: :P, name: "Ann", age: 30}) == "Ann is 30"
    end

    test "interpolation resolves across modules (program-wide ic, ADR-0069)" do
      # `mod B`'s hole references `mod A`'s struct field and function — resolvable because
      # interpolation runs as a program-wide pass, not per-module.
      src = ~S"""
      mod A do
        type S := S(name String)
        pub def label(n Int53) String := "L"
      end
      mod B do
        pub def f(s S, n Int53) String := "${s.name}/${A.label(n)}"
      end
      """

      {:ok, _} = Beam.load(src, :interp_xmod)
    end

    test "an `${inspect(x)}` hole resolves to String (host inspect — no `no Show` error)" do
      # `inspect` is host-coupled (the function pins to `:ex`), but its return type is
      # unambiguously String, so the hole resolves instead of erroring at parse. (Execution
      # is the emitter's concern, not the resolver's — this asserts the resolution.)
      [{_, %{elixir: elixir}}] = Decl.compile(~S|def dbg(x _Unk) String := "got ${inspect(x)}"|)
      assert elixir =~ "inspect"
    end

    test "a hole over an un-annotated local call resolves (call-result inference)" do
      # `tag` declares no return; its body (`<>`) is String, inferred and folded into
      # the resolver's `:funs`, so `${tag(n)}` resolves instead of erroring `no Show`.
      src = ~S"""
      mod M do
        pub def greet(n String) String := "count: ${tag(n)}"
        def tag(s) := s <> "!"
      end
      """

      {:ok, _} = Beam.load(src, :interp_callresult)
    end

    test "a hole bound by a `case` arm resolves to the scrutinee type (scope-aware)" do
      # `other` is introduced by the arm pattern, typed by the scrutinee (`String`);
      # the resolver threads that binding into the arm body's hole.
      src = ~S"""
      mod M do
        pub def f(s String) String := case s do
          "" -> "empty"
          other -> "got ${other}"
        end
      end
      """

      {:ok, _} = Beam.load(src, :interp_casearm)
    end
  end

  describe "the same source lowers to JS and Rust (ADR-0069 §3 — portable, no FFI)" do
    @src ~S|def greet(n Int53) String := "n is ${n}!"|

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
                 Pratt.parse(~S|"a ${x} b"|),
                 %{"x" => "String"},
                 %{}
               )

      # empty trailing literal dropped; flat list of parts, no nested `{:bin, "<>"}`
      assert parts == [{:str, "a "}, {:id, "x"}, {:str, " b"}]
    end

    test "the BEAM builds one binary; a multi-hole string runs correctly" do
      {:ok, m} =
        Beam.load(
          ~S|def m(a Int53, b Int53, c Int53) String := "${a}-${b}-${c}"|,
          :interp_join_beam
        )

      assert m.m(1, 2, 3) == "1-2-3"
    end

    test "a single-part interpolation stays the bare value (no join prim)" do
      # `"${name}"` (name : String) collapses to the identity — no concat at all
      assert Rian.Interp.resolve(Pratt.parse(~S|"${name}"|), %{"name" => "String"}, %{}) ==
               {:id, "name"}
    end
  end

  describe "Reach is honest about interpolation (ADR-0069 §4)" do
    test "an Int53 hole keeps the function all-target (the portability win)" do
      assert reach(~S|def g(n Int53) String := "n=${n}"|, "g").reach
             |> MapSet.to_list()
             |> Enum.sort() == [:ex, :js, :jvm, :rs]
    end

    test "an `Int` (arbitrary precision) hole inherits ADR-0064: off :rs/:jvm" do
      # `Int` reaches only [:ex, :js] (bignum gap on Rust/JVM), and interpolating
      # one inherits that — honestly, via the existing numeric blocker.
      assert reach(~S|def g(n Int) String := "n=${n}"|, "g").reach
             |> MapSet.to_list()
             |> Enum.sort() == [:ex, :js]
    end
  end

  describe "portable `Char` interpolation (ADR-0069 §6)" do
    @csrc ~S|def tag(c Char) String := "[${c}]"|

    test "a `Char` hole stringifies to its single character and runs on the BEAM" do
      {:ok, m} = Beam.load(@csrc, :interp_char_beam)
      assert m.tag(?A) == "[A]"
      # a supplementary codepoint (emoji) round-trips through `<<cp::utf8>>`
      assert m.tag(0x1F600) == "[😀]"
    end

    test "the `Char` hole reaches all four targets (portable — atoms aside, Char is)" do
      assert reach(@csrc, "tag").reach |> MapSet.to_list() |> Enum.sort() ==
               [:ex, :js, :jvm, :rs]
    end

    test "JS lowers a `Char` hole to `String.fromCodePoint` and runs under node" do
      js = JS.compile(@csrc)
      assert js =~ "String.fromCodePoint(Number(c))"
      # a Char arrives as its codepoint; `tag(65)` → "[A]"
      assert node_eval(js, "tag(65)") in [:no_node, "[A]"]
    end

    test "Rust lowers a `Char` hole to `.to_string()` on the native `char`" do
      rs = Lower.to_rust(hd(Decl.parse(@csrc).funcs), [], %{})
      assert rs =~ "c.to_string()"
    end
  end

  describe "a `Float64` hole auto-wires the portable `Show.float` (ADR-0069 §6)" do
    @fsrc ~S|def label(x Float64) String := "v = ${x}, half ${x / 2.0}"|

    test "the `Show` formatter is injected and runs on the BEAM (ECMAScript output)" do
      {:ok, m} = Beam.load(@fsrc, :interp_float_beam)
      # ECMA `Number::toString`: integer-valued -> no `.0`, shortest round-trip digits
      assert m.label(3.14) == "v = 3.14, half 1.57"
      assert m.label(1.0) == "v = 1, half 0.5"
      assert m.label(100.0) == "v = 100, half 50"
    end

    test "it reaches all four targets (the portability win)" do
      # `:jvm` included since the Tier-2 list/cons emitter landed; JVM `Show.float` is
      # byte-identical to ECMAScript on every double (its `__prim_float_repr` searches
      # for the shortest round-trip, ADR-0069 §6) — no caveat.
      assert reach(@fsrc, "label").reach |> MapSet.to_list() |> Enum.sort() ==
               [:ex, :js, :jvm, :rs]
    end

    test "JS lowers the cross-module `Show.float` call to a flat `float(…)` and runs" do
      js = JS.compile(@fsrc)
      assert js =~ "float(x)"
      # the injected formatter is flattened into the same module
      assert js =~ "function float("
      assert node_eval(js, "label(1.0)") in [:no_node, "v = 1, half 0.5"]
    end

    test "a `Float32` hole is rejected — widen to `Float64` (ADR-0069)" do
      err =
        assert_raise ArgumentError, fn ->
          Beam.load(~S|def f(x Float32) String := "x=${x}"|, :interp_f32_err)
        end

      assert Exception.message(err) =~ "Float32"
      assert Exception.message(err) =~ "Float64"
    end
  end

  describe "a user type with `impl Show for T` interpolates via `show/1` (ADR-0069 §6)" do
    @sum_src """
    type Color := Red | Green | Blue
    protocol Show do
      def show(self Self) String
    end
    impl Show for Color do
      def show(c) := case c do
        Red -> "red"
        Green -> "green"
        Blue -> "blue"
      end
    end
    def describe(c Color) String := "color = ${c}!"
    def demo_red() String := describe(Red)
    def demo_blue() String := describe(Blue)
    """

    test "a sum-typed hole dispatches to the user impl and runs on the BEAM" do
      {:ok, m} = Beam.load(@sum_src, :interp_usershow_sum)
      assert m.demo_red() == "color = red!"
      assert m.demo_blue() == "color = blue!"
    end

    test "the hole lowers to a `show(…)` call (resolved statically by the hole's type)" do
      out = Decl.parse(@sum_src)
      describe = Enum.find(out.funcs, &(&1.name == "describe"))

      assert {:block, [expr: {:call, {:id, "__prim_str_concat_all"}, parts}]} =
               hd(describe.clauses).body

      assert Enum.any?(parts, &match?({:call, {:id, "show"}, [id: "c"]}, &1))
    end

    test "user-`Show` over a sum reaches every target (ADR-0042)" do
      # Rust monomorphises the `Show` impls behind a trait; the JVM lowers the dispatcher
      # to a `when (a0)` over `is <Type>` (both toolchain-verified). The constructor-tag
      # atoms are portable `Symbol`s (ADR-0041), and the `String` return is concrete on
      # every target, so nothing pins `describe`.
      assert reach(@sum_src, "describe").reach |> MapSet.to_list() |> Enum.sort() == [
               :ex,
               :js,
               :jvm,
               :rs
             ]
    end

    test "a struct with an `impl Show` interpolates the whole value via `show/1`" do
      src = """
      struct Point(x Int64, y Int64)
      protocol Show do
        def show(self Self) String
      end
      impl Show for Point do
        def show(p) := "the-origin"
      end
      def label(p Point) String := "pt = ${p}"
      def demo() String := label(Point(x: 3, y: 4))
      """

      {:ok, m} = Beam.load(src, :interp_usershow_struct)
      assert m.demo() == "pt = the-origin"
    end

    test "a user type with NO `impl Show` is still the `no Show` compile error" do
      assert_raise ArgumentError, ~r/no `Show` for `Color`/, fn ->
        Beam.load(
          ~S"""
          type Color := Red | Green
          def f(c Color) String := "c=${c}"
          """,
          :interp_usershow_none
        )
      end
    end
  end

  describe "un-stringifiable holes are a compile error, never a silent fallback (ADR-0035)" do
    test "a genuine `:unknown` (real inference gap) is rejected" do
      assert_raise ArgumentError, ~r/no `Show` for|statically-known/, fn ->
        Beam.load(~S|def f(x Int64) String := "v=${g(x)}"|, :interp_unknown_err)
      end
    end

    test "a determined non-stringifiable type is rejected" do
      assert_raise ArgumentError, ~r/no `Show` for `Box`/, fn ->
        Decl.compile(~S|type Box := B(Int64)| <> "\n" <> ~S|def f(b val Box) String := "v=${b}"|)
      end
    end
  end

  describe "the `_Unk` draft marker defers, not errors (ADR-0069, 2026-06 debate)" do
    test "a hole over a `_Unk`-typed value passes through (a transpiler draft can parse)" do
      # `_Unk` is a deliberately-unsupplied type, not a proven-non-stringifiable one — the
      # resolver defers (value passes through) rather than failing the parse.
      [{_, %{elixir: elixir}}] = Decl.compile(~S|def f(x _Unk) String := "v=${x}"|)
      assert elixir =~ "v="
    end
  end
end

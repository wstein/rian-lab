defmodule Rian.LowerTest do
  use ExUnit.Case, async: false
  alias Rian.Lower

  defp types do
    [
      %{
        name: "Shape",
        variants: [
          %{ctor: "Circle", fields: [%{label: "radius", type: "Float64"}]},
          %{ctor: "Square", fields: [%{label: "side", type: "Float64"}]}
        ]
      }
    ]
  end

  defp area do
    %{
      name: "area",
      params: [%{name: "shape", type: "Shape", cap: :val}],
      ret: "Float64",
      clauses: [
        %{pats: [{:ctor, "Circle", [{:var, "r"}]}], body: "pi * r * r"},
        %{pats: [{:ctor, "Square", [{:var, "s"}]}], body: "s * s"}
      ]
    }
  end

  describe "Elixir emission" do
    test "multi-clause defs with tagged-tuple patterns and pi const" do
      out = Lower.compile(types(), area())
      assert out.elixir =~ "def area({:circle, r}) do :math.pi() * r * r end"
      assert out.elixir =~ "def area({:square, s}) do s * s end"
      assert out.elixir =~ "@type shape :: {:circle, float()} | {:square, float()}"
    end
  end

  describe "Rust emission" do
    test "enum + match with struct-variant patterns and PI const" do
      out = Lower.compile(types(), area())
      assert out.rust =~ "enum Shape {"
      assert out.rust =~ "Circle { radius: f64 }"
      assert out.rust =~ "Shape::Circle { radius: r } => std::f64::consts::PI * r * r,"
      assert out.rust =~ "Shape::Square { side: s } => s * s,"
    end
  end

  describe "exhaustiveness" do
    test "a non-exhaustive function lowers with a panic fallthrough (ADR-0036)" do
      # only the `Circle` clause — `Square` is uncovered. Rather than refuse to emit
      # (the old gate), Lower stamps `partial` and Rust gets a `_ => panic!(…)` arm —
      # the totality Rust's `match` needs, matching the BEAM/JS/JVM runtime no-match.
      bad = %{area() | clauses: [hd(area().clauses)]}

      out = Lower.compile(types(), bad)
      assert out.rust =~ ~s|_ => panic!("area: no clause matched"),|
      # Elixir clauses are total-by-`FunctionClauseError`, so no fallthrough arm.
      assert out.elixir =~ "def area"
    end

    @tag :rust
    test "a partial function's panic fallthrough compiles + runs under rustc" do
      case System.find_executable("rustc") do
        nil ->
          :ok

        rustc ->
          src =
            "mod M do\n  pub def init_of(xs val Vec(Int53)) Vec(Int53)\n" <>
              "  pub def init_of([_]) := []\n" <>
              "  pub def init_of([x | rest]) := [x | init_of(rest)]\nend\n"

          rust = Lower.rust_program(Rian.Decl.parse(src))
          assert rust =~ ~s|_ => panic!("init_of: no clause matched"),|

          dir = Path.join(System.tmp_dir!(), "rian_partial_#{System.unique_integer([:positive])}")
          File.mkdir_p!(dir)
          on_exit(fn -> File.rm_rf(dir) end)
          rs = Path.join(dir, "p.rs")
          # the covered path returns; the `_` arm exists only to satisfy rustc's totality
          File.write!(
            rs,
            rust <> "\nfn main() { assert_eq!(m::init_of(&[1,2,3]), vec![1,2]); }\n"
          )

          bin = Path.join(dir, "p")
          {out, code} = System.cmd(rustc, ["-A", "warnings", "--edition", "2021", rs, "-o", bin])
          assert code == 0, "rustc failed:\n#{out}"
          assert {_, 0} = System.cmd(bin, [])
      end
    end

    @tag :rust
    test "a value union inside a `mod` narrows + runs under rustc — param AND return (ADR-0083)" do
      case System.find_executable("rustc") do
        nil ->
          :ok

        rustc ->
          # the synthesized `enum` is at the crate root; the `mod` must `use super::*` to
          # see it, and the union `case` must not crash the exhaustiveness gate inside a
          # `mod`. `roundtrip` exercises a union RETURN (wrap) feeding a union PARAM
          # (describe) — both narrowed — without `main` constructing the enum directly.
          src = """
          mod M do
            pub def describe(x Int53 | String) Int53 := case x do
              n Int53 -> n + 1
              s String -> 0
            end
            pub def wrap(b Bool) Int53 | String := if b do 41 else "x" end
            pub def roundtrip(b Bool) Int53 := describe(wrap(b))
          end
          """

          rust = Lower.rust_program(Rian.Decl.parse(src))
          assert rust =~ "use super::*;"

          dir =
            Path.join(System.tmp_dir!(), "rian_modunion_#{System.unique_integer([:positive])}")

          File.mkdir_p!(dir)
          on_exit(fn -> File.rm_rf(dir) end)
          rs = Path.join(dir, "u.rs")

          File.write!(
            rs,
            rust <>
              ~s|\nfn main() { assert_eq!(m::roundtrip(true), 42); assert_eq!(m::roundtrip(false), 0); println!("ok"); }\n|
          )

          bin = Path.join(dir, "u")
          {out, code} = System.cmd(rustc, ["-A", "warnings", "--edition", "2021", rs, "-o", bin])
          assert code == 0, "mod-union rustc failed:\n#{out}"
          assert {"ok\n", 0} = System.cmd(bin, [])
      end
    end

    @tag :rust
    test "a union binding nested in a branch passed to a union param compiles + runs (ADR-0083)" do
      case System.find_executable("rustc") do
        nil ->
          :ok

        rustc ->
          # `y := mk(b)` is bound INSIDE the `if` branch, so `union_locals` doesn't track
          # it and the `describe(y)` call gets a redundant `Enum::from(y)`. That is an
          # identity via Rust's reflexive `From<T> for T` — so it compiles and runs (no
          # `:rs` residual, contrary to the earlier ADR note).
          src = """
          mod M do
            pub def mk(b Bool) Int53 | String := if b do 41 else "x" end
            pub def describe(x Int53 | String) Int53 := case x do
              n Int53 -> n + 1
              s String -> 0
            end
            pub def f(b Bool) Int53 := if b do y := mk(b) ; describe(y) else 0 end
          end
          """

          rust = Lower.rust_program(Rian.Decl.parse(src))
          # the redundant identity wrap is present (and harmless)
          assert rust =~ "describe(RUnion_Int53_String::from(y))"

          dir = Path.join(System.tmp_dir!(), "rian_nestuni_#{System.unique_integer([:positive])}")
          File.mkdir_p!(dir)
          on_exit(fn -> File.rm_rf(dir) end)
          rs = Path.join(dir, "n.rs")

          File.write!(
            rs,
            rust <>
              ~s|\nfn main() { assert_eq!(m::f(true), 42); assert_eq!(m::f(false), 0); println!("ok"); }\n|
          )

          bin = Path.join(dir, "n")
          {out, code} = System.cmd(rustc, ["-A", "warnings", "--edition", "2021", rs, "-o", bin])
          assert code == 0, "nested-union rustc failed:\n#{out}"
          assert {"ok\n", 0} = System.cmd(bin, [])
      end
    end

    test "refuses to emit when a clause is unreachable" do
      dead = %{
        area()
        | clauses: [
            %{pats: [{:var, "any"}], body: "0.0"},
            %{pats: [{:ctor, "Circle", [{:var, "r"}]}], body: "r"}
          ]
      }

      assert_raise RuntimeError, ~r/unreachable/, fn -> Lower.compile(types(), dead) end
    end
  end

  describe "expression lowering (operator table)" do
    test "integer div / float div diverge per target" do
      assert Lower.emit_expr("n div 2", :elixir) == "div(n, 2)"
      assert Lower.emit_expr("n div 2", :rust) == "n / 2"
      assert Lower.emit_expr("a / b", :elixir) == "a / b"
      assert Lower.emit_expr("a / b", :rust) == "(a as f64) / (b as f64)"
    end

    test "pipe desugars to a structural call on every target (Core lowers `|>`, BEAM can't)" do
      # `|>` is desugared to a plain call in `Core.from_expr` so every backend — incl.
      # the abstract-forms BEAM emitter — lowers it as a call, not a `|>` operator.
      assert Lower.emit_expr("x |> f(y) |> g", :elixir) == "g(f(x, y))"
      assert Lower.emit_expr("x |> f(y) |> g", :rust) == "g(f(x, y))"
    end

    test "concat is native on Elixir, flattened format! on Rust" do
      assert Lower.emit_expr("s <> t <> u", :elixir) == "s <> t <> u"
      assert Lower.emit_expr("s <> t <> u", :rust) == ~s|format!("{}{}{}", s, t, u)|
    end

    test "boolean operators map to symbols on Rust" do
      assert Lower.emit_expr("a and not b", :elixir) == "a and not b"
      assert Lower.emit_expr("a and not b", :rust) == "a && !b"
    end

    test "precedence is preserved without redundant parens" do
      assert Lower.emit_expr("a + b * c", :rust) == "a + b * c"
      assert Lower.emit_expr("(a + b) * c", :rust) == "(a + b) * c"
    end
  end

  describe "emitted Elixir executes correctly" do
    test "area on real values matches expected" do
      out = Lower.compile(types(), area())
      Code.eval_string("defmodule AreaGenTest do\n#{out.elixir}\nend")
      assert_in_delta apply(AreaGenTest, :area, [{:circle, 2.0}]), :math.pi() * 4, 1.0e-9
      assert apply(AreaGenTest, :area, [{:square, 3.0}]) == 9.0
    end
  end

  describe "higher-order application on the Elixir text target (no Beam drift)" do
    defp ex_of(src, name) do
      # compile units key by `"name/arity"` (arity overloading); these single-arity
      # sources are looked up by bare name.
      {_, %{elixir: e}} =
        Rian.Decl.compile(src) |> Enum.find(&(elem(&1, 0) |> String.split("/") |> hd() == name))

      e
    end

    test "a function-valued parameter is applied with `f.(x)`, a local call stays `f(x)`" do
      src = """
      def apply_twice(f Fn(Int64, Int64), x Int64) Int64 := f(f(x))
      def add1(n Int64) Int64 := n + 1
      def go() Int64 := apply_twice(&add1/1, 5)
      """

      # the param `f` is in scope -> variable application
      assert ex_of(src, "apply_twice") =~ "f.(f.(x))"
      # `apply_twice` is a local function (not in scope) -> local call
      assert ex_of(src, "go") =~ "apply_twice(&add1/1, 5)"
    end

    test "a `:=`-bound function value is applied with `g.(x)`" do
      src = """
      def add1(n Int64) Int64 := n + 1
      def run(x Int64) Int64 := g := &add1/1 ; g(x)
      """

      assert ex_of(src, "run") =~ "g = &add1/1; g.(x)"
    end

    test "the emitted higher-order Elixir actually runs" do
      src = """
      def apply_twice(f Fn(Int64, Int64), x Int64) Int64 := f(f(x))
      def add1(n Int64) Int64 := n + 1
      """

      ex = Rian.Decl.compile(src) |> Enum.map_join("\n", fn {_, o} -> o.elixir end)
      Code.eval_string("defmodule HoGenTest do\n#{ex}\nend")
      assert apply(HoGenTest, :apply_twice, [&(&1 + 1), 5]) == 7
    end
  end

  # ─────────────────────────────────────────────────────────────────────────
  # Added coverage: per-node emit/2 clauses and the higher-level entry points.
  # ─────────────────────────────────────────────────────────────────────────

  alias Rian.{Decl, Pratt}

  describe "single-node expression emission" do
    test "dotted access lowers to `head::name` on Rust" do
      assert Lower.emit_expr("M.x", :rust) == "m::x"
    end

    test "unary minus on both targets" do
      assert Lower.emit_expr("-x", :rust) == "-x"
      assert Lower.emit_expr("-x", :elixir) == "-x"
    end

    test "`rem` is a function on Elixir, `%` on Rust" do
      assert Lower.emit_expr("a rem b", :elixir) == "rem(a, b)"
      assert Lower.emit_expr("a rem b", :rust) == "a % b"
    end

    test "`or` maps to `||` on Rust" do
      assert Lower.emit_expr("a or b", :rust) == "a || b"
    end

    test "a `Symbol` (`:foo`) keeps its atom on Elixir and lowers to a `&str` on Rust (ADR-0041)" do
      assert Lower.emit_expr(":foo", :elixir) == ":foo"
      assert Lower.emit_expr(":foo", :rust) == ~s|"foo"|
    end
  end

  describe "`&` capture arity over each node kind (Rust closure params)" do
    test "dot, unary, if, call, and list bodies all count placeholders" do
      assert Lower.emit_expr("&(&1.x)", :rust) == "|a1| a1::x"
      assert Lower.emit_expr("&(-&1)", :rust) == "|a1| -a1"
      assert Lower.emit_expr("&(if &1 do 1 else 2 end)", :rust) == "|a1| if a1 { 1 } else { 2 }"
      assert Lower.emit_expr("&(f(&1, &2))", :rust) == "|a1, a2| f(a1, a2)"
      assert Lower.emit_expr("&([&1, &2])", :rust) == "|a1, a2| vec![a1, a2]"
    end

    test "a map body's placeholder is counted before the BEAM-only raise" do
      # cap_arity over %EMap{} runs (string interpolation evaluates it first),
      # then the map-literal emit raises — exercising the EMap cap_arity clause.
      assert_raise RuntimeError, ~r/map literals are BEAM-only/, fn ->
        Lower.emit_expr("&(%{a: &1})", :rust)
      end
    end

    test "a nullary named capture yields an empty closure parameter list" do
      assert Lower.emit_expr("&foo/0", :rust) == "|| foo()"
    end
  end

  describe "Rust char literals (ADR-0036)" do
    test "escaped specials are emitted with their Rust escape" do
      assert Lower.emit_expr("'\\n'", :rust) == "'\\n'"
      assert Lower.emit_expr("'\\t'", :rust) == "'\\t'"
      assert Lower.emit_expr("'\\r'", :rust) == "'\\r'"
      assert Lower.emit_expr("'\\\\'", :rust) == "'\\\\'"
      # the NUL and single-quote codepoints (built as AST — they don't lex cleanly)
      assert Lower.emit_ast({:char, 0}, :rust) == "'\\0'"
      assert Lower.emit_ast({:char, ?'}, :rust) == "'\\''"
    end
  end

  describe "block emission (typed binds + empty blocks)" do
    test "a typed `:=` bind inside a block erases its annotation per target" do
      ast = Pratt.parse_body("n Int64 := 1 ; n")
      assert Lower.emit_ast(ast, :elixir) == "n = 1; n"
      assert Lower.emit_ast(ast, :rust) == "let n = 1; n"
    end

    test "an empty block is `nil` on Elixir, `()` on Rust" do
      assert Lower.emit_ast(Pratt.parse_body("if c do else 1 end"), :elixir) ==
               "if c do nil else 1 end"

      assert Lower.emit_ast(Pratt.parse_body("if c do 1 else end"), :rust) ==
               "if c { 1 } else { () }"
    end
  end

  describe "case arm with a `when` guard" do
    test "guard lowers to `when` on Elixir and `if` on Rust" do
      ast = Pratt.parse_body("case x do\n  n when n > 0 -> 1\n  _ -> 0\nend")
      assert Lower.emit_ast(ast, :elixir) == "case x do n when n > 0 -> 1; _ -> 0 end"
      assert Lower.emit_ast(ast, :rust) == "match x { n if n > 0 => 1, _ => 0, }"
    end
  end

  describe "module compilation (compile_module / compile_module_beam)" do
    defp geo_mod do
      Decl.parse("""
      mod Geo do
        struct Point(x Int64, y Int64)
        pub def mk(a Int64, b Int64) Point := Point(x: a, y: b)
      end
      """).mods
      |> hd()
    end

    test "compile_module emits a defmodule and a Rust mod with a pub struct" do
      out = Lower.compile_module(geo_mod())
      assert out.elixir =~ "defmodule Geo do"
      assert out.elixir =~ "defmodule Point do defstruct [:x, :y] end"
      assert out.rust =~ "mod geo {"
      assert out.rust =~ "pub struct Point { pub x: i64, pub y: i64 }"
      assert out.rust =~ "Point { x: a, y: b }"
    end

    test "compile_module_beam emits only the Elixir view" do
      out = Lower.compile_module_beam(geo_mod())
      assert Map.keys(out) == [:elixir]
      assert out.elixir =~ "def mk(a, b) do %Point{x: a, y: b} end"
    end
  end

  describe "compile_elixir/4 (Elixir-only entry)" do
    test "emits only the Elixir clauses + typespec" do
      out = Lower.compile_elixir(types(), area())
      assert Map.keys(out) == [:elixir]
      assert out.elixir =~ "def area({:circle, r}) do :math.pi() * r * r end"
      assert out.elixir =~ "@type shape :: {:circle, float()}"
    end
  end

  describe "Rust call-site borrow insertion (ADR-0047)" do
    test "an owned String/Vec arg to a borrowing param gets a `&`" do
      str_mod =
        Decl.parse("""
        mod S do
          pub def use_it(s val String) Int64 := 0
          pub def caller(a val String, b val String) Int64 := use_it(__prim_str_concat(a, b))
        end
        """).mods
        |> hd()

      rust = Lower.compile_module(str_mod).rust
      # __prim_str_concat produces an owned String -> borrowed into the &str param
      assert rust =~ "use_it(&format!(\"{}{}\", a, b))"

      vec_mod =
        Decl.parse("""
        mod V do
          pub def make() Vec(Int64) := [1, 2]
          pub def take(xs val Vec(Int64)) Int64 := 0
          pub def caller2() Int64 := take(make())
        end
        """).mods
        |> hd()

      # a call returning Vec(...) is owned -> borrowed into the &[T] param
      assert Lower.compile_module(vec_mod).rust =~ "take(&make())"

      from_chars_mod =
        Decl.parse("""
        mod C do
          pub def use_it(s val String) Int64 := 0
          pub def caller(cs val Vec(Char)) Int64 := use_it(__prim_str_from_chars(cs))
        end
        """).mods
        |> hd()

      # __prim_str_from_chars produces an owned String -> borrowed into &str
      assert Lower.compile_module(from_chars_mod).rust =~ "use_it(&cs.iter().collect::<String>())"

      string_ret_mod =
        Decl.parse("""
        mod R do
          pub def make() String := "x"
          pub def take(s val String) Int64 := 0
          pub def caller2() Int64 := take(make())
        end
        """).mods
        |> hd()

      # a call whose return type is `String` is owned -> borrowed into &str
      assert Lower.compile_module(string_ret_mod).rust =~ "take(&make())"
    end
  end

  describe "Rust protocol lowering (ADR-0061)" do
    test "a `&self`-only method over a sum type emits a trait + impl" do
      p =
        Decl.parse("""
        protocol Show do
          def show(self Self) String
        end
        type Color := Red | Green
        impl Show for Color do
          def show(c) := "color"
        end
        """)

      rust = Lower.rust_protocols(p.protocols, p.impl_decls, p.types, p.structs)
      assert rust =~ "enum Color {"
      assert rust =~ "trait RianShow {"
      assert rust =~ "fn show(&self) -> String;"
      assert rust =~ "impl RianShow for Color {"
      assert rust =~ "let c = self;"
    end

    test "a binary method over a struct impl borrows its extra Self/typed params" do
      p =
        Decl.parse("""
        protocol Eq do
          def eq(self Self, other Self) Bool
          def tag(self Self, n Int64) Int64
        end
        struct Box(v Int64)
        impl Eq for Box do
          def eq(a, b) := true
          def tag(a, n) := n
        end
        """)

      rust = Lower.rust_protocols(p.protocols, p.impl_decls, p.types, p.structs)
      # the struct the impl targets is emitted alongside (impl-type filter)
      assert rust =~ "struct Box { v: i64 }"
      # an extra `Self` param -> `&Box`; a primitive param keeps its borrowed type
      assert rust =~ "fn eq(&self, b: &Box) -> bool"
      assert rust =~ "fn tag(&self, n: i64) -> i64"
    end

    test "an associated type lowers to `type Elem: Clone;` (trait, `Self::Elem`) + `type Elem = i64;` (impl) — ADR-0074" do
      p =
        Decl.parse("""
        protocol Foldable do
          type Elem
          def first(self Self) Elem
        end
        type Bag := Bag(items Vec(Int53))
        impl Foldable for Bag do
          type Elem := Int53
          def first(b) := case b do Bag(xs) -> 0 end
        end
        """)

      rust = Lower.rust_protocols(p.protocols, p.impl_decls, p.types, p.structs)
      # trait: declares the associated type (with the `Clone` bound every Rian tvar
      # carries, so a consumer passing the element to a generic helper type-checks) and
      # projects it as `Self::Elem`
      assert rust =~ "trait RianFoldable {\n    type Elem: Clone;"
      assert rust =~ "fn first(&self) -> Self::Elem;"
      # impl: binds the associated type to the concrete Rust type, ret resolved
      assert rust =~ "impl RianFoldable for Bag {\n    type Elem = i64;"
      assert rust =~ "fn first(&self) -> i64 {"
    end

    @tag :rust
    test "the emitted associated-type trait + impl compiles and runs under rustc (ADR-0074)" do
      case System.find_executable("rustc") do
        nil ->
          :ok

        rustc ->
          p =
            Decl.parse("""
            protocol Foldable do
              type Elem
              def first(self Self) Elem
            end
            type Bag := Bag(items Vec(Int53))
            impl Foldable for Bag do
              type Elem := Int53
              def first(b) := case b do Bag(xs) -> 7 end
            end
            """)

          dir = System.tmp_dir!()
          src = Path.join(dir, "rian_assoc_#{System.unique_integer([:positive])}.rs")
          bin = String.trim_trailing(src, ".rs")

          File.write!(
            src,
            Lower.rust_program(p) <>
              "\nfn main() { let b = Bag::Bag { items: vec![1,2,3] }; " <>
              "assert_eq!(b.first(), 7); println!(\"ok\"); }\n"
          )

          {_, 0} =
            System.cmd(rustc, ["--edition", "2021", src, "-o", bin], stderr_to_stdout: true)

          {out, 0} = System.cmd(bin, [])
          File.rm(src)
          File.rm(bin)
          assert String.trim(out) == "ok"
      end
    end

    @tag :rust
    test "a `Symbol` function compiles and runs under rustc — `&str`/`String` (ADR-0041)" do
      case System.find_executable("rustc") do
        nil ->
          :ok

        rustc ->
          p =
            Decl.parse("def tag(s Symbol) Symbol\ndef tag(:ok) := :done\ndef tag(_) := :other\n")

          dir = System.tmp_dir!()
          src = Path.join(dir, "rian_sym_#{System.unique_integer([:positive])}.rs")
          bin = String.trim_trailing(src, ".rs")

          File.write!(
            src,
            Lower.rust_program(p) <>
              ~s|\nfn main() { assert_eq!(tag("ok"), "done"); assert_eq!(tag("x"), "other"); println!("ok"); }\n|
          )

          {_, 0} =
            System.cmd(rustc, ["--edition", "2021", src, "-o", bin], stderr_to_stdout: true)

          {out, 0} = System.cmd(bin, [])
          File.rm(src)
          File.rm(bin)
          assert String.trim(out) == "ok"
      end
    end

    @tag :rust
    test "a `Symbol` literal passed to a generic `&K` param compiles (owned-borrow, ADR-0041)" do
      case System.find_executable("rustc") do
        nil ->
          :ok

        rustc ->
          # `pick`'s params are a generic `&K`; calling it with Symbol literals must
          # owned-borrow them (`&"ok".to_string()`), not emit a bare `&str` (rustc E0277).
          p =
            Decl.parse("def pick(a T, b T) T forall T := a\ndef go() Symbol := pick(:ok, :no)")

          dir = System.tmp_dir!()
          src = Path.join(dir, "rian_symg_#{System.unique_integer([:positive])}.rs")
          bin = String.trim_trailing(src, ".rs")

          File.write!(
            src,
            Lower.rust_program(p) <>
              ~s|\nfn main() { assert_eq!(go(), "ok"); println!("ok"); }\n|
          )

          {_, 0} =
            System.cmd(rustc, ["--edition", "2021", src, "-o", bin], stderr_to_stdout: true)

          {out, 0} = System.cmd(bin, [])
          File.rm(src)
          File.rm(bin)
          assert String.trim(out) == "ok"
      end
    end
  end

  describe "rust_program (whole-program assembly)" do
    test "emits every non-dispatch function once" do
      prog =
        Decl.parse("""
        def inc(n Int64) Int64 := n + 1
        def dbl(n Int64) Int64 := n * 2
        """)

      rust = Lower.rust_program(prog)
      assert rust =~ "fn inc(n: i64) -> i64"
      assert rust =~ "fn dbl(n: i64) -> i64"
    end
  end

  describe "Rust pattern-emission edge cases" do
    test "a string-literal clause head lowers to a `&str` match arm" do
      rust =
        Decl.compile("""
        def kind(t String) Int64
        def kind("def") := 1
        def kind(_) := 0
        """)
        |> Enum.map_join("\n", fn {_, o} -> o.rust end)

      assert rust =~ ~s|"def" => 1,|
    end

    test "a cons pattern with a wildcard tail uses `[h, ..]`" do
      rust =
        Decl.compile("""
        def head(xs Vec(Int64)) Int64
        def head([h | _]) := h
        def head([]) := 0
        """)
        |> Enum.map_join("\n", fn {_, o} -> o.rust end)

      assert rust =~ "[h, ..] =>"
      assert rust =~ "[] => 0,"
    end

    test "a tuple-inside-cons binder is deref'd in the guard (list in guard too)" do
      rust =
        Decl.compile("""
        def f(xs Vec(Int64)) Bool
        def f([c | _]) when c == hd([c]) := true
        def f(_) := false
        """)
        |> Enum.map_join("\n", fn {_, o} -> o.rust end)

      # the slice-element binder `c` is a `&T`, so the guard deref's it (`*c`),
      # and the list literal `[c]` in the guard is walked by `deref_ids`
      assert rust =~ "if *c == hd(vec![*c])"
    end

    test "a `Symbol` pattern matches the interned name as a `&str` literal on Rust (ADR-0041)" do
      func = %{
        name: "h",
        params: [%{name: "x", type: "Symbol", cap: :val}],
        ret: "Int64",
        clauses: [
          %{pats: [{:atom, "foo"}], body: "1"},
          %{pats: [{:var, "x"}], body: "0"}
        ]
      }

      rust = Lower.to_rust(func, [], %{})
      assert rust =~ "fn h(x: &str)"
      assert rust =~ ~s|"foo" => 1|
    end
  end

  describe "construction with a mix of positional and named fields is rejected" do
    test "a variant constructor mix raises" do
      types = [
        %{
          name: "P",
          variants: [
            %{ctor: "Pt", fields: [%{label: "x", type: "Int64"}, %{label: "y", type: "Int64"}]}
          ]
        }
      ]

      func = %{name: "f", params: [], ret: "P", clauses: [%{pats: [], body: "Pt(1, y: 2)"}]}

      assert_raise RuntimeError, ~r/variant Pt: mix of positional and named/, fn ->
        Lower.compile(types, func)
      end
    end

    test "a struct constructor mix raises" do
      structs = [
        %{name: "Q", fields: [%{label: "x", type: "Int64"}, %{label: "y", type: "Int64"}]}
      ]

      func = %{name: "g", params: [], ret: "Q", clauses: [%{pats: [], body: "Q(1, y: 2)"}]}

      assert_raise RuntimeError, ~r/struct Q: mix of positional and named/, fn ->
        Lower.compile([], func, structs)
      end
    end
  end

  describe "Char reaches the Elixir typespec path (prim_ex)" do
    test "a Char-typed variant field types as `char()`" do
      ctypes = [%{name: "Tok", variants: [%{ctor: "Ch", fields: [%{label: "c", type: "Char"}]}]}]

      func = %{
        name: "g",
        params: [%{name: "t", type: "Tok", cap: :val}],
        ret: "Int64",
        clauses: [%{pats: [{:ctor, "Ch", [{:var, "c"}]}], body: "c"}]
      }

      assert Lower.to_elixir(func, ctypes) =~ "@type tok :: {:ch, char()}"
    end
  end

  describe "string-literal escaping (full Elixir/Gleam set)" do
    test "quotes/newlines/control chars emit valid Elixir and Rust literals" do
      assert Lower.emit_expr(~S|"\t\"$\a"|, :elixir) == ~S|"\t\"$\u{7}"|
      assert Lower.emit_expr(~S|"\t\"$\a"|, :rust) == ~S|"\t\"$\u{7}"|

      {v, _} = Code.eval_string(Lower.emit_expr(~S|"\t\"$\a"|, :elixir))
      assert v == "\t\"$" <> <<7>>
    end

    @tag :rust
    test "the emitted Rust string literal compiles and decodes under rustc" do
      case System.find_executable("rustc") do
        nil ->
          :ok

        rustc ->
          lit = Lower.emit_expr(~S|"\t\"$\a"|, :rust)
          dir = System.tmp_dir!()
          src = Path.join(dir, "rian_str_#{System.unique_integer([:positive])}.rs")
          bin = String.trim_trailing(src, ".rs")

          File.write!(
            src,
            "fn main() { let s = #{lit}; " <>
              "println!(\"{}\", s.chars().map(|c| (c as u32).to_string()).collect::<Vec<_>>().join(\",\")); }"
          )

          {_, 0} =
            System.cmd(rustc, ["--edition", "2021", src, "-o", bin], stderr_to_stdout: true)

          {out, 0} = System.cmd(bin, [])
          File.rm(src)
          File.rm(bin)
          assert String.trim(out) == "9,34,36,7"
      end
    end
  end

  describe "String-returning functions lower to an owned Rust `String` (coerce_ret)" do
    @str_src ~S|mod S do
  pub def s() String := "hi"
  pub def label(n Int64) String
  pub def label(0) := "zero"
  pub def label(_) := "other"
  pub def greet(name String) String := "hi " <> name
end|

    test "each clause arm is coerced to String, leaving non-String returns alone" do
      [{_, %{rust: rust}}] = Rian.Decl.compile(@str_src)
      # &str-literal arms gain `.to_string()`; the owned-String return type holds
      assert rust =~ ~S|() => ("hi").to_string(),|
      assert rust =~ ~S|0 => ("zero").to_string(),|
      assert rust =~ "pub fn greet(name: &str) -> String"
      # an Int64-returning function is untouched (no spurious coercion)
      [{_, %{rust: r2}}] = Rian.Decl.compile("def dbl(n Int64) Int64 := n * 2")
      refute r2 =~ "to_string()"
    end

    test "Reach claims :rs and the emitter now produces it (matrix matches emitter)" do
      rep = @str_src |> Rian.Decl.parse() |> Rian.Reach.analyze()
      for f <- ~w(s/0 label/1 greet/1), do: assert(:rs in MapSet.to_list(rep[f].reach))
    end

    @tag :rust
    test "the emitted Rust compiles and runs under rustc" do
      case System.find_executable("rustc") do
        nil ->
          :ok

        rustc ->
          [{_, %{rust: rust}}] = Rian.Decl.compile(@str_src)
          dir = System.tmp_dir!()
          path = Path.join(dir, "rian_coerce_#{System.unique_integer([:positive])}.rs")
          bin = String.trim_trailing(path, ".rs")

          File.write!(
            path,
            rust <>
              "\nfn main() { println!(\"{} {} {}\", s::s(), s::label(0), s::greet(\"bob\")); }"
          )

          {_, 0} =
            System.cmd(rustc, ["--edition", "2021", path, "-o", bin], stderr_to_stdout: true)

          {out, 0} = System.cmd(bin, [])
          File.rm(path)
          File.rm(bin)
          assert String.trim(out) == "hi zero hi bob"
      end
    end
  end

  describe "a returned closure over a type variable lowers to a boxed `dyn Fn` (ADR-0061)" do
    @clo_src """
    def adder(x T) Fn(T, T) forall T := (n) -> x
    def mk(x T) Fn(Int53, T) forall T := (n) -> x
    """

    test "owns the captured tvar, bounds it `Clone + 'static`, and clones the body per call" do
      rust = Rian.Lower.rust_program(Rian.Decl.parse(@clo_src))
      # owned param `x: T` (not `&T`), `'static` bound, `Box<dyn Fn>`, and a per-call clone
      assert rust =~ "fn adder<T: Clone + 'static>(x: T) -> Box<dyn Fn(T) -> T>"
      assert rust =~ "fn mk<T: Clone + 'static>(x: T) -> Box<dyn Fn(i64) -> T>"
      assert rust =~ "Box::new(move |n| (x).clone())"
    end

    @tag :rust
    test "the emitted Rust compiles and runs under rustc (a reusable `Fn`)" do
      case System.find_executable("rustc") do
        nil ->
          :ok

        rustc ->
          rust = Rian.Lower.rust_program(Rian.Decl.parse(@clo_src))
          dir = System.tmp_dir!()
          path = Path.join(dir, "rian_clo_#{System.unique_integer([:positive])}.rs")
          bin = String.trim_trailing(path, ".rs")

          File.write!(
            path,
            rust <>
              "\nfn main() { let f = adder(7i64); let g = mk(String::from(\"hi\")); " <>
              "println!(\"{} {} {}\", f(0), f(0), g(99)); }"
          )

          {_, 0} =
            System.cmd(rustc, ["--edition", "2021", path, "-o", bin], stderr_to_stdout: true)

          {out, 0} = System.cmd(bin, [])
          File.rm(path)
          File.rm(bin)
          # `f` is called twice — the closure clones its captured `T`, so it is a reusable `Fn`
          assert String.trim(out) == "7 7 hi"
      end
    end
  end

  describe "Result-of-String coerces the Ok payload to owned String (ADR-0040/0061)" do
    @res_src ~S"""
    mod R do
      type Oops := Bad
      pub def get(n Int64) Result(String, Oops)
      pub def get(0) := {:error, Bad}
      pub def get(_) := {:ok, "hi"}
    end
    """

    test "the `Ok(...)` payload gains `.to_string()`; `Err` (non-String) is untouched" do
      [{_, %{rust: rust}}] = Rian.Decl.compile(@res_src)
      assert rust =~ "-> Result<String, Oops>"
      # the string-literal payload is owned by `rust_owned_elem` (`"hi".to_string()`),
      # not double-wrapped by `result_payload` (ADR-0041 owned-element coercion)
      assert rust =~ ~S|Ok("hi".to_string())|
      # the error arm carries a non-String error type, so it is NOT coerced
      assert rust =~ "Err(Oops::Bad)"
      refute rust =~ ~S|Err(("|
    end

    @tag :rust
    test "the emitted Result<String, _> Rust compiles and runs under rustc" do
      case System.find_executable("rustc") do
        nil ->
          :ok

        rustc ->
          [{_, %{rust: rust}}] = Rian.Decl.compile(@res_src)
          dir = System.tmp_dir!()
          path = Path.join(dir, "rian_result_str_#{System.unique_integer([:positive])}.rs")
          bin = String.trim_trailing(path, ".rs")

          File.write!(
            path,
            rust <>
              "\nfn main() { match r::get(1) { Ok(s) => println!(\"{}\", s), Err(_) => {} } }"
          )

          {_, 0} =
            System.cmd(rustc, ["--edition", "2021", path, "-o", bin], stderr_to_stdout: true)

          {out, 0} = System.cmd(bin, [])
          File.rm(path)
          File.rm(bin)
          assert String.trim(out) == "hi"
      end
    end
  end

  describe "Elixir emission — maps & bitstrings" do
    defp elixir_of(src) do
      %{mods: [m | _]} = Rian.Decl.parse(src)
      Lower.compile_module_beam(m).elixir
    end

    test "a computed-key (`=>`) map pair emits alongside atom-key shorthand" do
      out = elixir_of("mod M do\n  pub def f(k Int53) Int53 := %{k => 1, a: 2}\nend")
      assert out =~ "%{k => 1, a: 2}"
    end

    test "bitstring segments emit type/size/unit specs" do
      out = elixir_of("mod M do\n  pub def f(x Int53) Binary := <<x::8, 1::16-unit(2)>>\nend")
      assert out =~ "<<x::8, 1::16-unit(2)>>"
    end
  end
end

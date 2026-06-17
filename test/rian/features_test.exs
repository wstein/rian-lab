defmodule Rian.FeaturesTest do
  use ExUnit.Case, async: false
  alias Rian.Lower

  # `Feat` is compiled into the VM at runtime by a test (Code.eval_string), so it is
  # undefined at compile time — don't warn on the references to it.
  @compile {:no_warn_undefined, [Feat]}

  setup_all do
    fns = [
      {"dbl_all", "xs", "Enum.map(xs, (x) -> x * 2)"},
      {"sum", "xs", ":lists.foldl((x, acc) -> x + acc, 0, xs)"},
      {"sign", "n", "if n >= 0 do 1 else 0 - 1 end"},
      {"step", "n", "if n > 0 do a := n * 2; a + 1 else 0 end"},
      {"nums", "_x", "[10, 20, 30]"},
      {"pre", "p", "[p | [1, 2]]"},
      {"rec", "_x", "%{a: 1, b: 2}"}
    ]

    defs =
      Enum.map_join(fns, "\n", fn {name, param, body} ->
        f = %{
          name: name,
          params: [%{name: param, type: "term", cap: :val}],
          ret: "term",
          clauses: [%{pats: [{:var, param}], body: body}]
        }

        Lower.compile_beam([], f).elixir |> String.split("\n") |> List.last()
      end)

    Code.eval_string("defmodule Feat do\n#{defs}\nend")
    :ok
  end

  describe "lambda lowering" do
    test "Elixir anonymous fn / Rust closure" do
      assert Lower.emit_expr("(x) -> x * 2", :elixir) == "fn x -> x * 2 end"
      assert Lower.emit_expr("(x) -> x * 2", :rust) == "|x| x * 2"
      assert Lower.emit_expr("(x, acc) -> x + acc", :elixir) == "fn x, acc -> x + acc end"
    end

    test "lambda inside an FFI call" do
      assert Lower.emit_expr(":lists.foldl((x, acc) -> x + acc, 0, xs)", :elixir) ==
               ":lists.foldl(fn x, acc -> x + acc end, 0, xs)"
    end
  end

  describe "if / block lowering" do
    test "if-expression" do
      assert Lower.emit_expr("if n >= 0 do 1 else 0 - 1 end", :elixir) ==
               "if n >= 0 do 1 else 0 - 1 end"

      assert Lower.emit_expr("if n >= 0 do 1 else 0 - 1 end", :rust) ==
               "if n >= 0 { 1 } else { 0 - 1 }"
    end

    test "block with a binding" do
      assert Lower.emit_expr("if n > 0 do a := n * 2; a + 1 else 0 end", :elixir) ==
               "if n > 0 do a = n * 2; a + 1 else 0 end"

      assert Lower.emit_expr("if n > 0 do a := n * 2; a + 1 else 0 end", :rust) ==
               "if n > 0 { let a = n * 2; a + 1 } else { 0 }"
    end
  end

  describe "list / map literal lowering" do
    test "list literal" do
      assert Lower.emit_expr("[1, 2, 3]", :elixir) == "[1, 2, 3]"
      assert Lower.emit_expr("[1, 2, 3]", :rust) == "vec![1, 2, 3]"
    end

    test "cons construction (Rust: prepend onto an owned copy of the tail, ADR-0047)" do
      assert Lower.emit_expr("[h | t]", :elixir) == "[h | t]"
      # cons lowers to a block that prepends onto `tail.to_vec()` (a Vec)
      assert Lower.emit_expr("[h | t]", :rust) ==
               "{ let mut __v = t.to_vec(); __v.insert(0, h); __v }"
    end

    test "map literal (BEAM-only)" do
      assert Lower.emit_expr("%{a: 1, b: 2}", :elixir) == "%{a: 1, b: 2}"
      assert_raise RuntimeError, ~r/BEAM-only/, fn -> Lower.emit_expr("%{a: 1, b: 2}", :rust) end
    end

    test "map update `%{base | k: v}` (parse → Core → Elixir text / Rust BEAM-only)" do
      assert Rian.Pratt.parse("%{m | k: 9}") == {:map_update, {:id, "m"}, [{"k", {:num, "9"}}]}
      assert Lower.emit_expr("%{m | k: 9, n: 0}", :elixir) == "%{m | k: 9, n: 0}"

      assert_raise RuntimeError, ~r/BEAM-only/, fn ->
        Lower.emit_expr("%{m | k: 9}", :rust)
      end
    end
  end

  describe "cons-recursion lowers to Rust slice patterns (ADR-0047)" do
    @cons_src """
    mod NumList do
      pub def sum(xs Vec(Int64)) Int64
      pub def sum([]) := 0
      pub def sum([h | t]) := h + sum(t)

      pub def countdown(n Int64) Vec(Int64)
      pub def countdown(0) := []
      pub def countdown(n) := [n | countdown(n - 1)]
    end
    """

    test "a cons pattern becomes a slice pattern; cons construction prepends onto a Vec" do
      [{_, %{rust: rust}}] = Rian.Decl.compile(@cons_src)

      # `[h | t]` clause head -> Rust slice pattern; the head is rebound owned
      # (`clone`) at arm entry, the tail slice is passed straight to the recursion
      assert rust =~ "[h, t @ ..] => { let h = h.clone(); h + sum(t) }"
      # `[n | countdown(n - 1)]` -> prepend onto an owned copy of the tail
      assert rust =~ "let mut __v = countdown(n - 1).to_vec(); __v.insert(0, n); __v"
    end

    @tag :rust
    test "the emitted Rust compiles and runs under rustc" do
      case System.find_executable("rustc") do
        nil ->
          :ok

        rustc ->
          [{_, %{rust: rust}}] = Rian.Decl.compile(@cons_src)
          dir = System.tmp_dir!()
          src = Path.join(dir, "rian_cons_#{System.unique_integer([:positive])}.rs")
          bin = String.trim_trailing(src, ".rs")

          File.write!(
            src,
            rust <>
              "\nfn main() { println!(\"{} {:?}\", num_list::sum(&num_list::countdown(4)), num_list::countdown(4)); }"
          )

          {_, 0} = System.cmd(rustc, ["-O", "--edition", "2021", src, "-o", bin])
          {out, 0} = System.cmd(bin, [])
          File.rm(src)
          File.rm(bin)
          assert String.trim(out) == "10 [4, 3, 2, 1]"
      end
    end

    @iso_src """
    mod ListOps do
      pub def cat(xs iso Vec(Int64), ys iso Vec(Int64)) Vec(Int64)
      pub def cat([], ys) := ys
      pub def cat([h | t], ys) := [h | cat(t, ys)]

      pub def rev(xs iso Vec(Int64)) Vec(Int64)
      pub def rev([]) := []
      pub def rev([h | t]) := cat(rev(t), [h | []])
    end
    """

    test "an `iso Vec` cons fn that returns/rebuilds a list matches .as_slice() + owned rebinds" do
      [{_, %{rust: rust}}] = Rian.Decl.compile(@iso_src)

      # owned param -> matched via `.as_slice()`; binders rebound to owned values
      assert rust =~ "match (xs.as_slice(), ys)"
      assert rust =~ "let h = h.clone(); let t = t.to_vec();"
      # returning a (non-matched, owned) param directly is allowed
      assert rust =~ "([], ys) => ys,"
    end

    test "the call-site borrow pass inserts `&` for an owned arg into a `&[T]`/`&str` param" do
      # `count(__prim_str_chars(s))` passes an owned Vec into a `&[i64]` param
      [{_, %{rust: rust}}] = Rian.Decl.compile(File.read!("examples/rian/prelude_str.rian"))
      assert rust =~ "count(&"
    end

    test "explicit overflow ops lower to the native i64 methods; checked -> Option<i64>" do
      [{_, %{rust: rust}}] = Rian.Decl.compile(File.read!("examples/rian/prelude_int.rian"))

      assert rust =~ "a.wrapping_add(b)"
      assert rust =~ "a.saturating_add(b)"
      assert rust =~ "a.checked_add(b)"
      # the parametric prelude type lowers to a Rust generic (ADR-0047)
      assert rust =~ "-> Option<i64>"
    end

    @tag :rust
    test "the overflow ops compile and run under rustc (deterministic Int64 projection)" do
      case System.find_executable("rustc") do
        nil ->
          :ok

        rustc ->
          [{_, %{rust: rust}}] = Rian.Decl.compile(File.read!("examples/rian/prelude_int.rian"))
          dir = System.tmp_dir!()
          src = Path.join(dir, "rian_int_#{System.unique_integer([:positive])}.rs")
          bin = String.trim_trailing(src, ".rs")

          File.write!(
            src,
            rust <>
              """
              fn main() {
                  use int::*;
                  assert_eq!(wrapping_add(i64::MAX, 1), i64::MIN);
                  assert_eq!(saturating_add(i64::MAX, 100), i64::MAX);
                  assert_eq!(checked_add(2, 3), Some(5));
                  assert_eq!(checked_add(i64::MAX, 1), None);
                  println!("ok");
              }
              """
          )

          {_, 0} = System.cmd(rustc, ["-O", "--edition", "2021", src, "-o", bin])
          {out, 0} = System.cmd(bin, [])
          File.rm(src)
          File.rm(bin)
          assert String.trim(out) == "ok"
      end
    end

    test "a type named in a `pub` fn's signature is emitted `pub` (cross-module usable)" do
      rust =
        File.read!("test/fixtures/rian/lexer.rian")
        |> Rian.Decl.compile()
        |> Enum.map_join("\n", fn {_, %{rust: r}} -> r end)

      # `pub fn tokenize(...) -> Vec<Token>` forces `Token` to be a `pub enum`
      assert rust =~ "pub enum Token"
    end

    @tag :rust
    test "the FFI-free lexer lowers to Rust and runs under rustc — called cross-module" do
      case System.find_executable("rustc") do
        nil ->
          :ok

        rustc ->
          rust =
            File.read!("test/fixtures/rian/lexer.rian")
            |> Rian.Decl.compile()
            |> Enum.map_join("\n", fn {_, %{rust: r}} -> r end)

          dir = System.tmp_dir!()
          src = Path.join(dir, "rian_lex_#{System.unique_integer([:positive])}.rs")
          bin = String.trim_trailing(src, ".rs")

          # the pub enum + pub fn means external code can name `Token` and call it
          File.write!(
            src,
            "#![allow(dead_code)]\n#{rust}\nfn main() { let ts: Vec<lexer::Token> = lexer::tokenize(\"12 + 3 * 4\"); println!(\"{}\", ts.len()); }"
          )

          {_, 0} = System.cmd(rustc, ["--edition", "2021", src, "-o", bin])
          {out, 0} = System.cmd(bin, [])
          File.rm(src)
          File.rm(bin)
          # [TNum(12), TPlus, TNum(3), TStar, TNum(4)] = 5 tokens
          assert String.trim(out) == "5"
      end
    end

    @guarded_src """
    mod Counter do
      pub def count_spaces(cs Vec(Int64)) Int64
      pub def count_spaces([]) := 0
      pub def count_spaces([c | t]) when c == 32 := 1 + count_spaces(t)
      pub def count_spaces([_ | t]) := count_spaces(t)
    end
    """

    test "a guard over a borrowed cons binder is dereffed (`*c`) on Rust" do
      [{_, %{rust: rust}}] = Rian.Decl.compile(@guarded_src)
      # `c` is `&i64` under the slice match -> the guard derefs it
      assert rust =~ "[c, t @ ..] if *c == 32 =>"
    end

    @tag :rust
    test "the guarded cons function compiles and runs under rustc" do
      case System.find_executable("rustc") do
        nil ->
          :ok

        rustc ->
          [{_, %{rust: rust}}] = Rian.Decl.compile(@guarded_src)
          dir = System.tmp_dir!()
          src = Path.join(dir, "rian_grd_#{System.unique_integer([:positive])}.rs")
          bin = String.trim_trailing(src, ".rs")

          File.write!(
            src,
            rust <> "\nfn main() { println!(\"{}\", counter::count_spaces(&[32,1,32,2])); }"
          )

          {_, 0} = System.cmd(rustc, ["-O", "--edition", "2021", src, "-o", bin])
          {out, 0} = System.cmd(bin, [])
          File.rm(src)
          File.rm(bin)
          assert String.trim(out) == "2"
      end
    end

    @tag :rust
    test "the `iso Vec` list-returning Rust compiles and runs under rustc" do
      case System.find_executable("rustc") do
        nil ->
          :ok

        rustc ->
          [{_, %{rust: rust}}] = Rian.Decl.compile(@iso_src)
          dir = System.tmp_dir!()
          src = Path.join(dir, "rian_iso_#{System.unique_integer([:positive])}.rs")
          bin = String.trim_trailing(src, ".rs")

          File.write!(
            src,
            rust <>
              "\nfn main() { println!(\"{:?} {:?}\", list_ops::cat(vec![1,2], vec![3,4]), list_ops::rev(vec![1,2,3])); }"
          )

          {_, 0} = System.cmd(rustc, ["-O", "--edition", "2021", src, "-o", bin])
          {out, 0} = System.cmd(bin, [])
          File.rm(src)
          File.rm(bin)
          assert String.trim(out) == "[1, 2, 3, 4] [3, 2, 1]"
      end
    end
  end

  describe "all three features execute on the BEAM" do
    test "lambdas (Enum.map / foldl)" do
      assert Feat.dbl_all([1, 2, 3]) == [2, 4, 6]
      assert Feat.sum([1, 2, 3, 4]) == 10
    end

    test "if and blocks" do
      assert Feat.sign(-5) == -1
      assert Feat.sign(7) == 1
      assert Feat.step(3) == 7
      assert Feat.step(-1) == 0
    end

    test "list and map literals" do
      assert Feat.nums(0) == [10, 20, 30]
      assert Feat.pre(0) == [0, 1, 2]
      assert Feat.rec(0) == %{a: 1, b: 2}
    end
  end
end

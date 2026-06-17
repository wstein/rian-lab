defmodule Rian.SelfhostBuildTest do
  # async: false — loads real modules into the VM via :code.load_binary.
  use ExUnit.Case, async: false

  alias Rian.Beam

  # Rian-FIRST behavioural tests: drive the **self-hosted Rian compiler** (the
  # composed `build`: LexerV2 → Decl → lower → Beam) with
  # real Rian programs and assert what they COMPUTE — no Elixir oracle in the loop.
  # The spec is the expected value, not `Rian.Decl`/`Rian.Beam`. This is the
  # Rian-first loop: a failing case here is a feature to add to the *Rian* sources.
  #
  # Known gaps (the backlog — programs `build` cannot yet compile; all fail LOUDLY,
  # not silently, so they are honest — add coverage as they land). None is needed by
  # the self-hosting bootstrap (the compiler sources avoid them); they are user sugar:
  #   * string interpolation `"…${e}…"` — blocked on type inference in the build
  #     loop (a hole is stringified by its static type, ADR-0069 §4); REFUSED loudly
  #     for now rather than silently mis-lowered (see the reject test below).
  #   * niche prims: i64 overflow ops (wrapping/saturating/checked_add) + float_repr.

  setup_all do
    for {mod, file} <- [
          {"LexerV2", "lexer_v2"},
          {"Decl", "decl"},
          {"Beam", "beam"},
          {"Exhaust", "exhaust"},
          {"Cap", "cap"},
          {"Checker", "checker"}
        ] do
      {:ok, _} = Beam.load(File.read!("compiler/#{file}.rian"), :"Elixir.#{mod}")
    end

    {:ok, drv} =
      Beam.load(File.read!("compiler/compose_real_sum.rian"), :rian_selfhost_build)

    {:ok, drv: drv}
  end

  defp run(drv, src, fun, args) do
    mod = drv.build(src, :"rian_built_#{System.unique_integer([:positive])}")
    apply(mod, fun, args)
  end

  # {name, source, fun, args, expected} — each compiled + run by the self-hosted compiler.
  @programs [
    {"arithmetic", "def double(n Int53) Int53 := n * 2", :double, [5], 10},
    {"multi-clause recursion",
     "def fib(n Int53) Int53\ndef fib(0) := 0\ndef fib(1) := 1\ndef fib(n) := fib(n - 1) + fib(n - 2)",
     :fib, [10], 55},
    {"when guard",
     "def sign(n Int53) Int53\ndef sign(0) := 0\ndef sign(n) when n > 0 := 1\ndef sign(_) := -1",
     :sign, [-3], -1},
    {"if-expression", "def maxi(a Int53, b Int53) Int53 := if a > b do a else b end", :maxi,
     [3, 9], 9},
    {"sum type + ctor pattern",
     "type Opt := None | Some(Int53)\npub def get(o Opt, d Int53) Int53\n" <>
       "def get(None, d) := d\ndef get(Some(v), _) := v", :get, [{:some, 7}, 0], 7},
    {"cons-list recursion",
     "def len(xs Vec(Int53)) Int53\ndef len([]) := 0\ndef len([_ | t]) := 1 + len(t)", :len,
     [[1, 2, 3]], 3},
    {"string literal", "def tag() String := \"ok\"", :tag, [], "ok"},
    {"string `<>`", "def cat(a String, b String) String := a <> b", :cat, ["x", "y"], "xy"},
    {"case", "def cls(n Int53) Int53 := case n do\n  0 -> 100\n  m -> m\nend", :cls, [0], 100},
    {"Prim", "def cc(c Char) Int53 := Prim.char_code(c)", :cc, [?A], 65},
    {"alias", "alias N := Int53\ndef f(x N) N := x", :f, [5], 5},
    {"struct construct + field",
     "struct P(x Int53)\ndef mk(n Int53) Int53\n  p := P(x: n)\n  p.x\nend", :mk, [5], 5},
    {"tuple", "def pr(a Int53, b Int53) Tuple := {a, b}", :pr, [1, 2], {1, 2}},
    # `with` (ADR-0039): the parser keeps it as a node, the driver's lowering
    # desugars it to nested `case`. A clause that matches continues; a non-match
    # falls to the `else` arms, or (no `else`) returns the value.
    {"with (clause matches -> body)",
     "def f(p Tuple) Int53 := with {:ok, v} <- p do v else _ -> 0 end", :f, [{:ok, 5}], 5},
    {"with (clause fails -> else)",
     "def f(p Tuple) Int53 := with {:ok, v} <- p do v else _ -> 0 end", :f, [{:error, :bad}], 0},
    {"with (no else -> passthrough)", "def f(p Tuple) Int53 := with {:ok, v} <- p do v end", :f,
     [{:error, :bad}], {:error, :bad}},
    {"with (multi-clause, all match)",
     "def f(p Tuple, q Tuple) Int53 := with {:ok, a} <- p, {:ok, b} <- q do a + b else _ -> 0 end",
     :f, [{:ok, 3}, {:ok, 4}], 7},
    {"with (multi-clause, 2nd fails -> else)",
     "def f(p Tuple, q Tuple) Int53 := with {:ok, a} <- p, {:ok, b} <- q do a + b else _ -> 0 end",
     :f, [{:ok, 3}, {:error, :x}], 0},
    # map literal (ADR-0063 #2): the parser keeps `%{…}` as a `MapE` node; the
    # driver lowers it to a Core map and the backend emits a plain Erlang map
    # (atom keys, no `__struct__` tag). Values may be literals or expressions.
    {"map literal", "def m() Map := %{a: 1, b: 2}", :m, [], %{a: 1, b: 2}},
    {"map with expression values", "def wrap(n Int53) Map := %{ok: n, double: n * 2}", :wrap, [7],
     %{ok: 7, double: 14}},
    # float literal: the lexeme carries the `.`; selfhost_beam splits Int53/Float64
    # by inspecting it and parses the float with correct rounding (Prim.str_to_float),
    # so the emitted `float()` equals the source literal (no silent int-mangling).
    {"float literal", "def pi() Float64 := 3.14", :pi, [], 3.14},
    {"float through arithmetic", "def bump(x Float64) Float64 := x + 1.5", :bump, [3.0], 4.5},
    # module constant (DConst): a literal-valued `const` is inlined at its references
    # (a capitalized `K` would otherwise lower to a nullary-ctor atom `:k`).
    {"const reference", "const K Int53 := 42\ndef f() Int53 := K", :f, [], 42},
    {"const in arithmetic", "const BASE Int53 := 10\ndef g(n Int53) Int53 := n * BASE + 1", :g,
     [4], 41},
    {"float const", "const PI Float64 := 3.14\ndef area(r Float64) Float64 := PI * r * r", :area,
     [2.0], 12.56},
    # operator coverage: `/` (float div), `div`/`rem` (integer), `!=`, and unary
    # `not` all reach the driver's `op_atom`, mapped to the same Erlang op atoms the
    # oracle (`Rian.Beam.erl_op`) uses.
    {"float division", "def half(x Float64) Float64 := x / 2.0", :half, [3.0], 1.5},
    {"integer div/rem", "def dr(a Int53, b Int53) Tuple := {a div b, a rem b}", :dr, [17, 5],
     {3, 2}},
    {"not-equal", "def ne(a Int53, b Int53) Bool := a != b", :ne, [1, 2], true},
    {"unary not", "def neg(b Bool) Bool := not b", :neg, [true], false},
    # string escapes: the lexer decodes `\n`/`\t`/`\"`/`\\` to codepoints (reusing
    # char_esc), so an escaped string is the real bytes — not the literal backslash.
    {"string escape newline", ~S|def f() String := "a\nb"|, :f, [], "a\nb"},
    {"string escape quote", ~S|def f() String := "a\"b"|, :f, [], "a\"b"},
    # portable-prelude prims (ADR-0047): selfhost_beam lowers each to the same native
    # Erlang form as Rian.Beam — Map ops (`:maps` + map literal), `char_to_string`
    # (`<<cp/utf8>>`), `int_to_float`, and the variadic `str_concat_all` join.
    {"prim map put/get", "def f() Int53 := Prim.map_get(Prim.map_put(Prim.map_new(), :a, 7), :a)",
     :f, [], 7},
    {"prim map has", "def f() Bool := Prim.map_has(Prim.map_put(Prim.map_new(), :a, 1), :b)", :f,
     [], false},
    {"prim char_to_string", "def f() String := Prim.char_to_string('Z')", :f, [], "Z"},
    {"prim int_to_float", "def f() Float64 := Prim.int_to_float(3)", :f, [], 3.0},
    {"prim str_concat_all", "def f() String := Prim.str_concat_all(\"a\", \"b\", \"c\")", :f, [],
     "abc"},
    # struct PATTERN `P(field: pat, …)`: parses to a distinct StructP node (the `TId :`
    # lookahead distinguishes it from a positional sum-variant pattern) and lowers to a
    # `%{__struct__ := …, field := pat}` map pattern; the exhaustiveness gate treats it
    # as a wildcard (a struct is single-shape).
    {"struct pattern field",
     "struct P(x Int53, y Int53)\ndef gx(p P) Int53\ndef gx(P(x: a, y: _)) := a", :gx,
     [%{__struct__: :p, x: 5, y: 6}], 5},
    {"struct pattern roundtrip",
     "struct P(x Int53)\ndef gx(p P) Int53\ndef gx(P(x: v)) := v\ndef f() Int53 := gx(P(x: 9))",
     :f, [], 9},
    # lambdas `(params) -> body` (ADR-0042): a Core closure -> an Erlang `fun`
    # (BEAM captures lexically). Applying a fun-valued VARIABLE (a param) is variable
    # application `Var(args)`, distinguished from a local call by the global
    # function-name set (resolve_apply) — so higher-order functions work.
    {"lambda immediate apply", "def f() Int53 := ((x) -> x + 1)(5)", :f, [], 6},
    {"higher-order param",
     "def ap(g, n Int53) Int53 := g(n)\ndef f() Int53 := ap((x) -> x * 2, 5)", :f, [], 10},
    {"lambda closure over param",
     "def adder(n Int53) := (x) -> x + n\ndef f() Int53 := adder(10)(5)", :f, [], 15},
    {"two-param lambda",
     "def app2(g, a Int53, b Int53) Int53 := g(a, b)\n" <>
       "def f() Int53 := app2((x, y) -> x * y, 6, 7)", :f, [], 42},
    # niche prims (ADR-0035/0064/0069): the i64 two's-complement overflow ops and the
    # Float64 shortest-round-trip repr. `wrapping_add` overflows MAX_i64 to MIN_i64;
    # `checked_add` returns `:none` on overflow, `{:some, sum}` otherwise.
    {"prim wrapping_add (no overflow)",
     "def f(a Int64, b Int64) Int64 := Prim.wrapping_add(a, b)", :f, [40, 2], 42},
    {"prim wrapping_add (overflow wraps)",
     "def f(a Int64, b Int64) Int64 := Prim.wrapping_add(a, b)", :f,
     [9_223_372_036_854_775_807, 1], -9_223_372_036_854_775_808},
    {"prim saturating_add (caps at max)",
     "def f(a Int64, b Int64) Int64 := Prim.saturating_add(a, b)", :f,
     [9_223_372_036_854_775_807, 100], 9_223_372_036_854_775_807},
    {"prim checked_add (none on overflow)",
     "def f(a Int64, b Int64) Tuple := Prim.checked_add(a, b)", :f,
     [9_223_372_036_854_775_807, 1], :none},
    {"prim checked_add (some)", "def f(a Int64, b Int64) Tuple := Prim.checked_add(a, b)", :f,
     [40, 2], {:some, 42}},
    {"prim float_repr", "def f(x Float64) String := Prim.float_repr(x)", :f, [3.5], "3.5"},
    # string interpolation (ADR-0069), resolved AOT: each hole is stringified by its
    # STATIC type (declared param / literal) — Int → int_to_string, Char →
    # char_to_string, Float → float_repr, String → identity, Bool → if. NOT runtime
    # dispatch (which can't tell a Char from an Int on the BEAM).
    {"interp int param", ~S|def f(n Int53) String := "n=${n}"|, :f, [42], "n=42"},
    {"interp string param", ~S|def greet(name String) String := "hi ${name}!"|, :greet, ["Ada"],
     "hi Ada!"},
    {"interp float param", ~S|def f(x Float64) String := "x=${x}"|, :f, [3.5], "x=3.5"},
    {"interp char param", ~S|def f(c Char) String := "[${c}]"|, :f, [?A], "[A]"},
    {"interp bool param", ~S|def f(b Bool) String := "ok=${b}"|, :f, [true], "ok=true"},
    {"interp literal hole", ~S|def f() String := "v=${42}"|, :f, [], "v=42"},
    {"interp arithmetic hole", ~S|def f(n Int53) String := "double=${n * 2}"|, :f, [21],
     "double=42"},
    {"interp multi-hole", ~S|def pt(x Int53, y Int53) String := "(${x}, ${y})"|, :pt, [3, 4],
     "(3, 4)"},
    {"interp escaped dollar (literal, not a hole)", ~S|def f() String := "cost \$5"|, :f, [],
     "cost $5"}
  ]

  describe "the self-hosted Rian compiler compiles + runs real programs (no Elixir oracle)" do
    for {name, src, fun, args, want} <- @programs do
      @src src
      @fun fun
      @args args
      @want want
      test "#{name}", %{drv: drv} do
        assert run(drv, @src, @fun, @args) == @want
      end
    end
  end

  describe "honest rejects (gaps that must fail LOUDLY, not silently mis-compile)" do
    test "an interpolation hole whose type can't be resolved AOT is refused", %{drv: drv} do
      # ADR-0069 §4: the stringify is chosen by the hole's STATIC type. A bare hole
      # over an untyped lambda param can't be resolved, so the build refuses (the
      # documented `:unknown` limitation) rather than guessing — never a runtime guess.
      assert catch_error(run(drv, ~S|def f(g) Int53 := g("v=${q}")|, :f, [fn x -> x end])) ==
               {:unresolved_interp_hole, ""}
    end
  end
end

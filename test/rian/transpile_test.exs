defmodule Rian.TranspileTest do
  use ExUnit.Case, async: true

  alias Rian.Transpile

  defp rian(src), do: Transpile.transpile(src)
  defp test_mod(body), do: rian("defmodule MyTest do\n  use ExUnit.Case\n#{body}\nend")

  describe "incompatible/1 — the Rian-model-incompatible-construct gate (--check)" do
    test "flags a truthy `||` / `&&` (no truthy operators, ADR-0035)" do
      assert [line] = Transpile.incompatible("defmodule M do\n  def f(x), do: x || :d\nend")
      assert line =~ "truthy ||"
      assert Transpile.incompatible("defmodule M do\n  def g(x), do: x && h(x)\nend") != []
    end

    test "flags exception flow (`def … rescue`, errors-as-values ADR-0040)" do
      src = """
      defmodule M do
        def f(x) do
          g(x)
        rescue
          _ -> nil
        end
      end
      """

      assert [line] = Transpile.incompatible(src)
      assert line =~ "def rescue"
    end

    test "flags a multi-kind recovery def (`rescue` + `after` → `def rescue/after`)" do
      # several recovery kinds render slash-joined; the gate must still catch them —
      # a `def rescue/after …` marker would otherwise slip a single-kind-only regex.
      src = """
      defmodule M do
        def f(v) do
          g(v)
        rescue
          _ -> nil
        after
          cleanup()
        end
      end
      """

      assert [line] = Transpile.incompatible(src)
      assert line =~ "def rescue/after"
    end

    test "clean code (case / Map.get) is compatible — no markers" do
      src = """
      defmodule M do
        def f(x), do: (case x do
          nil -> :d
          v -> v
        end)
        def g(m, k), do: Map.get(m, k, :d)
      end
      """

      assert Transpile.incompatible(src) == []
    end

    test "host FFI is NOT an incompatibility — it is honest non-portability, not a concept clash" do
      # an Erlang remote call is a TODO_PORT/FFI marker, but it is legitimately
      # non-portable (Reach pins it off :rs/:js), not a Rian-*concept* violation.
      assert Transpile.incompatible("defmodule M do\n  def f, do: :erlang.unique_integer()\nend") ==
               []
    end

    test "a `@rian_host`-tagged def is a sanctioned boundary — its rescue is excluded" do
      tagged = """
      defmodule M do
        use Rian.Ann
        @rian_host "host boundary"
        def f(x) do
          g(x)
        rescue
          _ -> nil
        end
      end
      """

      # same body WITHOUT the tag is still flagged — proving the tag (not the shape)
      # is what excludes it.
      untagged = String.replace(tagged, ~s|  @rian_host "host boundary"\n|, "")

      assert Transpile.incompatible(tagged) == []
      assert [line] = Transpile.incompatible(untagged)
      assert line =~ "def rescue"
      assert Rian.Ann.host_funcs(tagged) == ["f"]
    end
  end

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

    test "an exception-only module (`defexception`) is dropped with a note, not a marker" do
      # A host exception struct (an emitter's `Unsupported`, a parser's `Error`) backs
      # a `@rian_host` raise/rescue boundary. Errors are values in Rian (ADR-0035), so
      # it has no Rian image — drop it (no `mod` shell, no `TODO[port]`), with an honest
      # note recording what was dropped and why.
      src = """
      defmodule Beam do
        defmodule Unsupported do
          @moduledoc "Raised on an unsupported construct."
          defexception [:message]
        end

        def f(x), do: x
      end
      """

      out = rian(src)

      assert out =~
               "# (dropped Elixir exception `Unsupported`: errors are values in Rian, ADR-0035)"

      refute out =~ "mod Unsupported"
      refute out =~ "defexception"
      refute out =~ "TODO[port]: defexception"
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

    test "a function-bearing nested module is HOISTED to a top-level `mod` (Rian is flat)" do
      src = "defmodule Outer do\n  defmodule Helper do\n    def h(x), do: x\n  end\nend"
      out = rian(src)
      # `Helper` becomes a sibling top-level module, not a nested one (which Rian's
      # flat `Decl` would drop) — both `mod`s start at column 0.
      assert out =~ "\nmod Outer do"
      assert out =~ "\nmod Helper do"
      assert out =~ "pub def h("
    end
  end

  describe "module-less source (bare top-level `def`s, no `defmodule`)" do
    test "a single bare `def` renders FLAT — no `mod … do` box, no indent" do
      out = rian("def double(n) do\n  n * 2\nend")
      assert out =~ "\npub def double(n _Unk) _Unk := n * 2\n"
      refute out =~ "mod "
      refute out =~ "TODO[port]: top-level"
    end

    test "multiple bare clauses group into one flat def with no module wrapper" do
      src =
        "def fib(0) do\n  0\nend\n\ndef fib(1) do\n  1\nend\n\ndef fib(n) do\n  fib(n - 1) + fib(n - 2)\nend"

      out = rian(src)
      assert out =~ "pub def fib(_Unk) _Unk"
      assert out =~ "pub def fib(0) := 0"
      assert out =~ "pub def fib(1) := 1"
      assert out =~ "pub def fib(n) := fib(n - 1) + fib(n - 2)"
      refute out =~ "mod "
    end

    test "a bare `@type` stays passive provenance ahead of the flat defs" do
      src =
        "@type opt :: :none | {:some, term()}\ndef get(:none, d) do\n  d\nend\n\ndef get({:some, v}, _) do\n  v\nend"

      out = rian(src)
      assert out =~ "# type: @type opt"
      assert out =~ "pub def get(:none, d) := d"
      assert out =~ "pub def get({:some, v}, _) := v"
      refute out =~ "mod "
    end

    test "a non-declaration top-level degrades per-statement, not to one opaque blob" do
      out = rian("IO.puts(\"hi\")\ndef f(x) do\n  x\nend")
      assert out =~ "# TODO[port]:"
      assert out =~ "pub def f(x _Unk) _Unk := x"
      refute out =~ "top-level is not a single"
    end
  end

  describe "ExUnit test blocks → `@test def` (ADR-0060)" do
    test "a test module is flattened to module-less `@test def`s (discoverable, macros in scope)" do
      out = test_mod(~S|  test "doubling works" do
    assert double(21) == 42
  end|)

      assert out =~ "@test def doubling_works() Bool := assert_eq(double(21), 42)"
      # NOT wrapped in `mod` (a `mod` hides @test defs + the injected macros), and
      # `use ExUnit.Case` is dropped (pure scaffolding), not left as a marker.
      refute out =~ "mod MyTest"
      refute out =~ "use ExUnit"
    end

    test "`assert`/`refute` map to the assertion macros, with ==/!= specialized" do
      out = test_mod(~S|  test "eq" do
    assert a() == b()
  end

  test "neq" do
    assert a() != b()
  end

  test "bare" do
    assert ok?()
  end

  test "refute eq" do
    refute a() == b()
  end

  test "refute bare" do
    refute bad?()
  end|)

      assert out =~ "@test def eq() Bool := assert_eq(a(), b())"
      assert out =~ "@test def neq() Bool := assert_neq(a(), b())"
      assert out =~ "@test def bare() Bool := assert(ok?())"
      assert out =~ "@test def refute_eq() Bool := assert_neq(a(), b())"
      assert out =~ "@test def refute_bare() Bool := refute(bad?())"
    end

    test "a multi-statement body becomes a block: binds preamble + and-combined asserts" do
      out = test_mod(~S|  test "several" do
    x = double(3)
    assert x == 6
    assert double(4) == 8
  end|)

      assert out =~ "@test def several() Bool do"
      assert out =~ "  x := double(3)"
      assert out =~ "  assert_eq(x, 6) and assert_eq(double(4), 8)"
      assert out =~ "\nend"
    end

    test "`assert_raise` has no Rian image (no exceptions, ADR-0035) — a marker" do
      out = test_mod(~S|  test "raises" do
    assert_raise ArgumentError, fn -> boom() end
  end|)

      assert out =~ "@test def raises() Bool := TODO_PORT("
      assert out =~ "assert_raise"
    end

    test "a match assertion `assert pat = e` → a case-based Bool, not a bind" do
      out = test_mod(~S|  test "matches ok" do
    assert {:ok, _} = parse("x")
  end

  test "refutes a match" do
    refute {:error, _} = parse("x")
  end|)

      # the Bool of "did it match" — never the old `assert(pat := expr)` (a bind).
      refute out =~ "assert({:ok"
      assert out =~ "@test def matches_ok() Bool := case parse(\"x\") do"
      assert out =~ "{:ok, _} -> true"
      assert out =~ "_ -> false"
      # refute flips the arms
      assert out =~ "{:error, _} -> false"
    end

    test "the test name slugifies to a valid Rian identifier" do
      out = test_mod(~S|  test "1 plus 1 (sanity!)" do
    assert one() == 1
  end|)

      # leading digit → `t_` prefix; punctuation/spaces → single `_`; trimmed.
      assert out =~ "@test def t_1_plus_1_sanity() Bool := assert_eq(one(), 1)"
    end

    test "a dynamic (interpolated) test name is not ported — stays a marker" do
      out = test_mod(~S|  test "run #{n}" do
    assert ok?()
  end|)

      refute out =~ "\n@test def"
      assert out =~ "TODO[port]"
    end

    test "a `describe` block flattens to group-prefixed `@test def`s (Rian is flat)" do
      out = test_mod(~S|  describe "addition" do
    test "adds" do
      assert add(1, 2) == 3
    end

    test "commutes" do
      assert add(1, 2) == add(2, 1)
    end
  end

  describe "negation" do
    test "negates" do
      refute neg(1) == 1
    end
  end|)

      assert out =~ "@test def addition_adds() Bool := assert_eq(add(1, 2), 3)"
      assert out =~ "@test def addition_commutes() Bool := assert_eq(add(1, 2), add(2, 1))"
      assert out =~ "@test def negation_negates() Bool := assert_neq(neg(1), 1)"
      refute out =~ "describe"
    end

    test "a verbose test name is capped at a word boundary (≤ 64 chars)" do
      out =
        test_mod(
          ~S|  test "this is a deliberately very long descriptive test name that exceeds the cap" do
    assert ok?()
  end|
        )

      [slug] = Regex.run(~r/@test def (\w+)\(\)/, out, capture: :all_but_first)
      assert byte_size(slug) <= 64
      # truncated at a `_` boundary — no dangling partial word, no trailing `_`
      refute String.ends_with?(slug, "_")
      assert out =~ "@test def #{slug}() Bool := assert(ok?())"
    end

    test "a long `describe` prefix is capped separately, so test names stay distinct" do
      # under a long group, the test-specific part must survive (not be eaten by the
      # prefix and collapse two tests to the same capped slug + a `_2` suffix).
      out =
        test_mod(~S|  describe "finite signature exhaustiveness (the load-bearing decision)" do
    test "clause heads covering the whole interval are total, no catch-all" do
      assert ok?()
    end

    test "missing a member is non-exhaustive so the gate refuses to emit" do
      assert blocked?()
    end
  end|)

      slugs = Regex.scan(~r/@test def (\w+)\(\)/, out, capture: :all_but_first) |> List.flatten()
      assert length(slugs) == 2
      # the group prefix is shared and bounded…
      assert Enum.all?(slugs, &String.starts_with?(&1, "finite_signature"))
      # …but each test keeps a distinguishing tail (no `_2` collision suffix)
      assert Enum.uniq(slugs) == slugs
      refute Enum.any?(slugs, &String.ends_with?(&1, "_2"))
      assert Enum.any?(slugs, &String.contains?(&1, "interval"))
      assert Enum.any?(slugs, &String.contains?(&1, "gate"))
    end

    test "colliding slugs get a numeric suffix (never silently merged into one def)" do
      # two identical names — Rian would treat same-name @test defs as one function.
      out = test_mod(~S|  test "same name" do
    assert a()
  end

  test "same name" do
    assert b()
  end|)

      assert out =~ "@test def same_name() Bool := assert(a())"
      assert out =~ "@test def same_name_2() Bool := assert(b())"
    end

    test "a `setup`/`setup_all` block has no Rian image — a marker, not a `@test def`" do
      out = test_mod(~S|  describe "with fixture" do
    setup do
      {:ok, x: 1}
    end

    test "uses it" do
      assert ok?()
    end
  end|)

      assert out =~ "# TODO[port]: setup do"
      assert out =~ "@test def with_fixture_uses_it() Bool := assert(ok?())"
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

    test "a bitstring construction + pattern → Rian `<<…>>` (ADR-0078, no marker)" do
      out =
        rian("""
        defmodule Bx do
          def first(<<c::utf8, rest::binary>>), do: c
          def first(_), do: 0
          def two(), do: <<104, 105>>
        end
        """)

      assert out =~ "first(<<c::utf8, rest::binary>>) := c"
      assert out =~ "<<104, 105>>"
      # no emitted marker (`TODO_PORT("…")`) — the draft header mentions the word, so
      # match the call-with-arg form, not a bare substring.
      refute out =~ ~s|TODO_PORT("|
    end

    test "a string-prefix pattern `\"pre\" <> rest` → a bitstring pattern (ADR-0078 Stage 4)" do
      out =
        rian("""
        defmodule Px do
          def kind("Fn(" <> _rest), do: 1
          def kind(_), do: 0
        end
        """)

      assert out =~ ~s|kind(<<"Fn(", _::binary>>) := 1|
      refute out =~ ~s|TODO_PORT("|
    end

    test "a pin `^x` in a clause head → Rian `^x` (ADR-0050, no marker)" do
      out =
        rian("""
        defmodule Px do
          def eq(x, ^x), do: true
          def eq(_, _), do: false
        end
        """)

      assert out =~ "eq(x, ^x) := true"
      refute out =~ ~s|TODO_PORT("|
    end

    test "defp is private (`def`, no `pub`) and OMITS hole types — params and return (ADR-0034)" do
      # a private function needn't declare its types — `Rian.InferLocal` recovers
      # them, so an unresolved param/return is omitted rather than printed as `_Unk`.
      out = rian("defmodule M do\n  defp f(x), do: x\nend")
      assert out =~ ~r/\n  def f\(x\) :=/
      refute out =~ "def f(x _Unk)"
    end

    test "a `pub def` (from Elixir `def`) KEEPS its return hole (declare-public)" do
      out = rian("defmodule M do\n  def f(x), do: x\nend")
      assert out =~ "pub def f(x _Unk) _Unk := x"
    end

    test "a private def omits its hole types entirely (no `_Unk` to fill)" do
      {_pub, ps} =
        {nil, Rian.Transpile.transpile_with_stats("defmodule M do\n  def f(x), do: x\nend")}

      {_priv, qs} =
        {nil, Rian.Transpile.transpile_with_stats("defmodule M do\n  defp f(x), do: x\nend")}

      # public f keeps 2 holes (param + return, declare-public); private f omits
      # both — Rian infers them, so there is nothing to fill.
      assert elem(ps, 1).holes == 2
      assert elem(qs, 1).holes == 0
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
    test "an Elixir as-pattern (`pat = var`) becomes Rian `var @ pat`, not a marker" do
      out = rian("defmodule M do\n  def f({:bin, op} = node), do: {node, op}\nend")
      assert out =~ "node @ {:bin, op}"
      refute out =~ ~s|TODO_PORT("as-pattern|
    end

    test "a construct with no Rian image (non-atom-key map literal) stays a greppable marker" do
      # field access, stdlib calls, and atom-key map *update* now lower; a non-atom
      # key (`%{expr => v}`) has no `key: value` spelling, so it stays a marker.
      out = rian("defmodule M do\n  def t(k), do: %{k => 1}\nend")
      assert out =~ "TODO_PORT"
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

    test "atom-keyed map update `%{base | k: v}` → Rian `%{base | k: v}` (no marker)" do
      out = rian("defmodule M do\n  def bump(m), do: %{m | k: 9, n: 0}\nend")
      assert out =~ "%{m | k: 9, n: 0}"
      body = out |> String.split("mod M do") |> List.last()
      refute body =~ "TODO"
    end

    test "multi-statement clause body → a block clause (`head` … `end`), not a one-liner" do
      out = rian("defmodule M do\n  def g(x) do\n    y = x + 1\n    z = y + 1\n    z\n  end\nend")
      # binds on their own indented lines, closed by `end` — far more readable than
      # the `;`-joined inline form.
      assert out =~ "pub def g(x _Unk) _Unk\n    y := x + 1\n    z := y + 1\n    z\n  end"
    end

    test "a single-statement clause body stays the inline `:= expr` form" do
      assert rian("defmodule M do\n  def d(x), do: x + x\nend") =~
               "pub def d(x _Unk) _Unk := x + x"
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

      assert out =~ ~s|const prims := ["a", "b", "c"]|
      assert out =~ "pub def names() _Unk := prims"
      # the reference is the bare const name, never the unlexable `@(prims)`
      refute out =~ "@(prims"
    end

    test "the `a` modifier of `~w` yields an atom list" do
      assert rian("defmodule M do\n  @ks ~w(a b)a\n  def k, do: @ks\nend") =~
               "const ks := [:a, :b]"
    end

    test "doc/metadata attributes (`@impl`, `@typedoc`, `@doc false`, `@external_resource`) are dropped, not flagged" do
      # these carry no runtime semantics — a `# TODO[port]` would falsely imply lost
      # behaviour, blocking the roundtrip over pure documentation/compile metadata.
      out =
        rian("""
        defmodule M do
          @typedoc "a token"
          @type t :: integer()
          @external_resource "priv/x"
          @doc false
          @impl true
          def c(x), do: x
        end
        """)

      refute out =~ "TODO[port]: @typedoc"
      refute out =~ "TODO[port]: @impl"
      refute out =~ "TODO[port]: @doc"
      refute out =~ "TODO[port]: @external_resource"
      assert out =~ "pub def c(x _Unk) _Unk := x"
    end

    test "a referenced directive-shaped attribute still lowers to a `const`" do
      # the value-reference rule is unchanged: an attribute read as a value is a const.
      out = rian("defmodule M do\n  @limit 10\n  def cap, do: @limit\nend")
      assert out =~ "const limit := 10"
    end
  end

  describe "operators with no direct Rian spelling" do
    test "Elixir list concat `++` lowers to the prelude `List.concat/2` (Rian has no `++`)" do
      out = rian("defmodule M do\n  def j(a, b), do: a ++ b\nend")
      assert out =~ "List.concat(a, b)"
      refute out =~ "a ++ b"
    end

    test "Elixir `raise` → Rian `panic` (the diverging abort, ADR-0035/0040)" do
      out =
        rian("""
        defmodule M do
          def a, do: raise(ArgumentError, "bad input")
          def b, do: raise("boom")
          def c, do: raise(SomeError)
        end
        """)

      assert out =~ ~s|:= panic("bad input")|
      assert out =~ ~s|:= panic("boom")|
      # a bare `raise Mod` panics with the error name
      assert out =~ ~s|:= panic("SomeError")|
      # never the invalid bare `raise(...)` (no such Rian builtin)
      body = out |> String.split("mod M do") |> List.last()
      refute body =~ "raise("
    end

    test "truthy `&&`/`||` become a TODO_PORT marker (no faithful Rian image)" do
      # Rian's `and`/`or` are boolean (they lower to native `&&`/`||`), so they are
      # NOT a sound port of Elixir's value-returning, nil-coalescing `&&`/`||`; the
      # self-host port restructures these to `case`/Option by hand. Emit an honest
      # marker rather than a wrong boolean op or an eager `&&(l, r)` call.
      out = rian("defmodule M do\n  def g(x), do: x && f(x)\n  def d(x, y), do: x || y\nend")
      assert out =~ ~s{TODO_PORT("truthy && (nil-coalescing)}
      assert out =~ ~s{TODO_PORT("truthy || (nil-coalescing)}
      # never the invalid eager call form, nor a silently-wrong boolean op.
      body = out |> String.split("mod M do") |> List.last()
      refute body =~ "&&("
      refute body =~ ":= x and f(x)"
    end
  end

  describe "operator precedence — parenthesize only when the Rian re-parse needs it" do
    test "a looser-binding left operand is parenthesized (`(13 - lvl) * 10`)" do
      # `*` binds tighter than `-`, so the `- ` subtree must be wrapped or the Rian
      # parser would read `13 - (lvl * 10)`.
      out = rian("defmodule M do\n  def bp(lvl), do: (13 - lvl) * 10\nend")
      assert out =~ ":= (13 - lvl) * 10"
    end

    test "no spurious parens when the operand already binds tighter (`a - b * c`)" do
      out = rian("defmodule M do\n  def k(a, b, c), do: a - b * c\nend")
      assert out =~ ":= a - b * c"
    end

    test "an `or` operand under `and` is parenthesized (boolean precedence)" do
      out = rian(~S|defmodule M do
        def vc(op, l, r), do: op == "x" and (vl(l) or vr(r))
      end|)

      assert out =~ ~s|:= op == "x" and (vl(l) or vr(r))|
    end

    test "a prefix `not` wraps any infix operand (`not (a or b)`)" do
      out = rian("defmodule M do\n  def f(a, b), do: not (a or b)\nend")
      assert out =~ ":= not (a or b)"
    end

    test "left-associativity is preserved without redundant parens (`a - b + c`)" do
      out = rian("defmodule M do\n  def f(a, b, c), do: a - b + c\nend")
      assert out =~ ":= a - b + c"
    end

    test "a right operand at the same level is parenthesized (`a - (b + c)`)" do
      out = rian("defmodule M do\n  def f(a, b, c), do: a - (b + c)\nend")
      assert out =~ ":= a - (b + c)"
    end
  end

  describe "`nil` renders as `None` consistently in expression AND pattern position" do
    test "a `nil` clause-head argument matches the `None` a producer emits" do
      # `nil` is an atom; without a dedicated clause it rendered the empty atom `:`,
      # which never matches the `None` of `expr(nil)` — silently breaking the match.
      out = rian("defmodule M do\n  def f(nil), do: :close\nend")
      assert out =~ "f(None) := :close"
      refute out =~ "f(:)"
    end

    test "a `nil` map *value* in a pattern renders `None` (`%{body: None}`)" do
      out = rian("defmodule M do\n  def f(%{body: nil} = s), do: s\nend")
      assert out =~ "%{body: None}"
      refute out =~ "%{body: :}"
    end

    test "a `nil` map *key* renders `None =>`, expression and pattern" do
      out =
        rian("""
        defmodule M do
          def t, do: %{nil => 0, cons: 2}
          def p(%{nil => v}), do: v
        end
        """)

      assert out =~ "%{None => 0, cons: 2}"
      assert out =~ "p(%{None => v}) := v"
    end

    test "a `nil` case arm renders `None ->`" do
      out =
        rian("""
        defmodule M do
          def f(x) do
            case x do
              nil -> :miss
              v -> v
            end
          end
        end
        """)

      assert out =~ "None -> :miss"
      refute out =~ ": -> :miss"
    end
  end

  describe "string literals are escaped for a re-lexable Rian literal" do
    test "a backslash in the value is doubled (was emitted raw, re-lexed as a control char)" do
      # source value is `a\b`; the Rian literal must double the backslash so it
      # re-lexes to the same value rather than to a `\b` escape.
      out =
        rian(~S'''
        defmodule M do
          def bs, do: "a\\b"
        end
        ''')

      assert out =~ ~S|"a\\b"|
      refute out =~ ~S|"a\b"|
    end

    test "a regex backreference `\\1` survives (collapse_parens-style replacement)" do
      out =
        rian(~S'''
        defmodule M do
          def c(s), do: Regex.replace(~r/x/, s, "\\1")
        end
        ''')

      assert out =~ ~S|"\\1"|
    end

    test "a newline in the value renders as the `\\n` escape, not a raw newline" do
      out =
        rian(~S'''
        defmodule M do
          def nl, do: "x\ny"
        end
        ''')

      assert out =~ ~S|"x\ny"|
    end
  end

  describe "exception flow (rescue/catch/after) surfaces as a marker, never dropped" do
    test "a `def … rescue …` becomes a TODO_PORT marker that keeps the happy path" do
      # Rian has no exceptions (ADR-0035/0040); the recovery clause has no Rian image,
      # so the def must be flagged for restructuring rather than emitting just `:do`.
      out =
        rian("""
        defmodule M do
          def f(v) do
            g(v)
          rescue
            _ -> nil
          end
        end
        """)

      assert out =~ ~s|:= TODO_PORT("def rescue|
      assert out =~ "restructure to Result/Option"
      # the happy path is preserved in the marker, not lost
      assert out =~ "happy path: g(v)"
    end

    test "a plain `def` (no recovery) is unaffected" do
      out = rian("defmodule M do\n  def f(x), do: x + 1\nend")
      assert out =~ ":= x + 1"
      # refute against the body only — the emitted header legend mentions TODO_PORT.
      body = out |> String.split("mod M do") |> List.last()
      refute body =~ "TODO_PORT"
    end

    test "a `@rian_host`-tagged rescue is a sanctioned boundary → happy path under a `# @rian_host:` note" do
      # `@rian_host` (Rian.Ann) marks a def whose recovery lives host-side on purpose
      # (ADR-0035/0048: the errors-as-values twin of a raising function). The recovery
      # has no Rian image, but the def is NOT unfinished work — so the draft emits the
      # portable happy path under a greppable host-boundary note, never a TODO_PORT.
      out =
        rian("""
        defmodule M do
          @rian_host "compile boundary: load/2 raises into a value"
          def load_result(src) do
            load(src)
          rescue
            e -> {:error, Exception.message(e)}
          end
        end
        """)

      assert out =~ "# @rian_host: compile boundary: load/2 raises into a value"
      assert out =~ ":= load(src)"
      body = out |> String.split("mod M do") |> List.last()
      refute body =~ "TODO_PORT"
    end
  end

  describe "struct/map updates desugar to the Rian map-update form" do
    test "struct update `%Mod{base | f: v}` → Rian `%{base | f: v}` (struct is a tagged map)" do
      # a Rian struct value is a tagged map (ADR-0043), so a struct update is the
      # map exact-assoc — preserving `__struct__`. No marker; field access in the
      # value (`p.t`) lowers too.
      out = rian("defmodule M do\n  def u(p), do: %P{p | type: p.t}\nend")
      assert out =~ "%{p | type: p.t}"
      body = out |> String.split("mod M do") |> List.last()
      refute body =~ "TODO"
    end

    test "map update `%{base | k: v}` → Rian `%{base | k: v}` (no marker)" do
      out = rian("defmodule M do\n  def u(m), do: %{m | k: 1}\nend")
      assert out =~ "%{m | k: 1}"
      body = out |> String.split("mod M do") |> List.last()
      refute body =~ "TODO"
    end

    test "non-atom map keys `%{key => v}` → Rian `=>` keys, literal + pattern (ADR-0033)" do
      out =
        rian("""
        defmodule M do
          def t, do: %{"a" => 1, b: 2}
          def p(%{"k" => v}), do: v
        end
        """)

      # a computed key renders `keyExpr => v`; a mixed atom key keeps the `k: v` shorthand.
      assert out =~ ~s|%{"a" => 1, b: 2}|
      assert out =~ ~s|p(%{"k" => v}) := v|
      body = out |> String.split("mod M do") |> List.last()
      refute body =~ "TODO"
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

    test "codepoint conversions map to Str (same prim lowering as the Elixir call)" do
      # String.to_charlist ≡ Str.chars; List.to_string ≡ Str.from_chars.
      assert rian("defmodule M do\n  def f(s), do: String.to_charlist(s)\nend") =~ "Str.chars(s)"

      assert rian("defmodule M do\n  def f(cs), do: List.to_string(cs)\nend") =~
               "Str.from_chars(cs)"
    end

    test "Enum.map → List.map with its lambda eta-translated" do
      out = rian("defmodule M do\n  def f(xs), do: Enum.map(xs, &(&1 + 1))\nend")
      assert out =~ "List.map(xs, (p1) -> p1 + 1)"
    end

    test "an Elixir-stdlib call with no portable image is emitted as BEAM FFI, not a marker" do
      # `MapSet.new` has no portable prelude image, so it lowers to a native remote
      # call (compiles/runs on BEAM, pinned off :rs/:js) rather than a TODO_PORT.
      out = rian("defmodule M do\n  def f(s), do: MapSet.new(s)\nend")
      assert out =~ "MapSet.new(s)"
      refute out =~ ~s|TODO_PORT("remote/stdlib call: MapSet.new|
    end

    test "an Erlang/atom-module call (`:erlang.fun`) is emitted as FFI, not a marker" do
      out = rian("defmodule M do\n  def f(b), do: :erlang.binary_to_atom(b, :utf8)\nend")
      assert out =~ ":erlang.binary_to_atom(b, :utf8)"
      refute out =~ ~s|TODO_PORT("remote/stdlib call: :erlang|
    end

    test "anonymous-function application `f.(x)` → Rian variable application `f(x)`" do
      out = rian("defmodule M do\n  def g(f, x), do: f.(x)\nend")
      assert out =~ ":= f(x)"
      refute out =~ ~s|TODO_PORT("f.(|
    end

    test "field access (`r.name`, chained) is Rian-native, not a marker" do
      out = rian("defmodule M do\n  def n(r), do: r.name\n  def c(x), do: x.a.b\nend")
      assert out =~ ":= r.name"
      assert out =~ ":= x.a.b"
      refute out =~ ~s|TODO_PORT("remote/stdlib call|
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

  describe "default arguments desugar into delegating clauses (arity overloading)" do
    test "a `\\\\`-default function expands to one delegating clause per default" do
      out =
        rian("""
        defmodule M do
          def f(a, opts \\\\ [], n \\\\ 0) do
            {a, opts, n}
          end
        end
        """)

      # the full clause plus one delegating clause per trailing default, exactly
      # like Elixir's desugaring — f/1 -> f/2 -> f/3
      assert out =~ "pub def f(a _Unk) _Unk := f(a, [], 0)"
      assert out =~ "pub def f(a _Unk, opts _Unk) _Unk := f(a, opts, 0)"
      assert out =~ "pub def f(a _Unk, opts _Unk, n _Unk) _Unk := {a, opts, n}"
      # no leftover `\\` and no port marker on the emitted body (the header always
      # mentions TODO_PORT generically — check the code after `mod M do`)
      body = out |> String.split("mod M do") |> List.last()
      refute body =~ "\\\\"
      refute body =~ "TODO"
    end

    test "a single trailing default yields exactly one delegator" do
      out =
        rian("""
        defmodule M do
          def greet(name, greeting \\\\ "hi") do
            greeting
          end
        end
        """)

      assert out =~ ~S|pub def greet(name _Unk) _Unk := greet(name, "hi")|
      assert out =~ "pub def greet(name _Unk, greeting _Unk) _Unk := greeting"
    end

    test "a bodyless default-declaring head + real clauses expands to delegators (multi-clause form)" do
      # Elixir requires defaults on a bodyless head when a function has multiple
      # clauses: `def f(a, b \\ d)` (no body) followed by the real clauses. The head
      # declares defaults for them; desugar to the delegators and drop the head.
      out =
        rian("""
        defmodule M do
          def check(func, ic \\\\ %{}, eset \\\\ %{tsets: %{}})
          def check(f, ic, eset), do: {f, ic, eset}
        end
        """)

      assert out =~ "pub def check(func _Unk) _Unk := check(func, %{}, %{tsets: %{}})"
      assert out =~ "pub def check(func _Unk, ic _Unk) _Unk := check(func, ic, %{tsets: %{}})"
      assert out =~ "pub def check(f _Unk, ic _Unk, eset _Unk) _Unk := {f, ic, eset}"
      body = out |> String.split("mod M do") |> List.last()
      refute body =~ "\\\\"
      refute body =~ "TODO"
    end

    test "a non-variable parameter alongside a default strips defaults to one clause" do
      # forwarding by name is unsound when a param is a pattern (not a plain var),
      # so the defaults are dropped to a single clause rather than mis-delegated.
      out =
        rian("""
        defmodule M do
          def f({x, y}, opts \\\\ []) do
            {x, y, opts}
          end
        end
        """)

      body = out |> String.split("mod M do") |> List.last()
      assert body =~ "pub def f("
      refute body =~ "\\\\"
      # no delegating clause was synthesised (a pattern param can't be forwarded by
      # name) — there is no `:= f(` self-call
      refute body =~ ":= f("
    end
  end

  describe "comprehensions desugar (ADR-0079)" do
    test "Elixir `for` → Rian `for … do … end` (generators + filter, no marker)" do
      out =
        rian("""
        defmodule M do
          def dbl(xs), do: for x <- xs, do: x * 2
          def pos(xs), do: for x <- xs, x > 0, do: x
          def grid(xs, ys), do: for x <- xs, y <- ys, do: {x, y}
        end
        """)

      assert out =~ "for x <- xs do x * 2 end"
      assert out =~ "for x <- xs, x > 0 do x end"
      assert out =~ "for x <- xs, y <- ys do {x, y} end"
      body = out |> String.split("mod M do") |> List.last()
      refute body =~ "TODO"
    end

    test "`into:` folds the list comprehension into a collection via prelude ops (ADR-0079)" do
      out =
        rian("""
        defmodule M do
          def s(cs), do: for c <- cs, into: "", do: c
          def m(ps), do: for {k, v} <- ps, into: %{}, do: {k, v}
        end
        """)

      # into: "" → a left-fold with `<>`; into: %{} → a fold with `Dict.put` (so Reach
      # inherits the map blocker). No new Rian surface — pure `List.reduce` desugar.
      assert out =~ ~s|List.reduce(for c <- cs do c end, "", (__e, __acc) -> __acc <> __e)|

      assert out =~
               "List.reduce(for {k, v} <- ps do {k, v} end, %{}, (__e, __acc) -> case __e do {__k, __v} -> Dict.put(__acc, __k, __v) end)"

      refute out =~ ~s|TODO_PORT("for comprehension|
    end

    test "the binary-comprehension porting idiom (`<<cp::utf8 <- s>>` → `String.to_charlist`) renders portably" do
      # A binary generator has no list image (it stays a marker, see below), so the
      # portable spelling iterates codepoints as a char list: `String.to_charlist/1`
      # maps to the portable `Str.chars`, and `into: ""` folds with `<>`. This is the
      # shape `Rian.{Lexer,Lower,JS,JVM}` use for string re-escaping.
      out = rian(~S|defmodule M do
  def esc(s), do: for cp <- String.to_charlist(s), into: "", do: cp_src(cp)
end|)

      assert out =~
               ~s|List.reduce(for cp <- Str.chars(s) do cp_src(cp) end, "", (__e, __acc) -> __acc <> __e)|

      refute out =~ ~s|TODO_PORT("for comprehension|
    end

    test "`reduce:` folds the loop into an accumulator via nested `List.reduce` (ADR-0079)" do
      out =
        rian("""
        defmodule M do
          def sum(xs) do
            for x <- xs, reduce: 0 do
              acc -> acc + x
            end
          end

          def collect(ps) do
            for p <- ps, m <- p.methods, reduce: [] do
              acc -> [m | acc]
            end
          end
        end
        """)

      assert out =~ "List.reduce(xs, 0, (x, __acc0) ->"
      # multiple generators nest, threading the same accumulator
      assert out =~
               "List.reduce(ps, [], (p, __acc0) -> List.reduce(p.methods, __acc0, (m, __acc1) ->"

      refute out =~ ~s|TODO_PORT("for comprehension|
    end

    test "a binary generator / unknown `into:` target stays an honest marker (ADR-0079)" do
      # `<<b <- bin>>` (binary comprehension) has no list image; `into: MapSet.new()` is
      # an unrecognized collectable — both stay markers rather than mis-render.
      bin = rian("defmodule M do\n  def bytes(s), do: for <<b <- s>>, do: b\nend")
      assert bin =~ ~s|TODO_PORT("for comprehension|

      other = rian("defmodule M do\n  def u(xs), do: for x <- xs, into: MapSet.new(), do: x\nend")
      assert other =~ ~s|TODO_PORT("for comprehension|
    end

    test "a destructuring / pattern-filtering generator → Rian `pat <- src` (no marker)" do
      out =
        rian("""
        defmodule M do
          def mods(decls), do: for {:mod, name, _inner} <- decls, do: name
          def keys(ps), do: for {k, _v} <- ps, do: k
        end
        """)

      # an underscore-prefixed binder renders as the anonymous `_`
      assert out =~ "for {:mod, name, _} <- decls do name end"
      assert out =~ "for {k, _} <- ps do k end"
      body = out |> String.split("mod M do") |> List.last()
      refute body =~ "TODO"
    end
  end

  describe "transpile_with_stats" do
    test "counts def groups and unresolved markers (header not self-counted)" do
      # a custom `@cfg` attribute has no Rian image → a real `# TODO[port]` marker
      # (doc/metadata attributes like `@impl` are dropped, ADR-0075); `Enum.x/1` is
      # BEAM FFI (not a marker). The DRAFT header documents `TODO_PORT`/`_Unk` by name
      # but must NOT inflate the tally — so ports is exactly the 1 marker.
      {_text, stats} =
        Transpile.transpile_with_stats(
          "defmodule M do\n  @cfg :raw\n  def a, do: Enum.x(1)\n  def b(z), do: z\nend"
        )

      assert stats.defs == 2
      assert stats.ports == 1
    end
  end
end

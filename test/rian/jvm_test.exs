defmodule Rian.JVMTest do
  use ExUnit.Case, async: true

  alias Rian.JVM

  # Each `kotlinc -include-runtime` invocation rebundles the whole Kotlin stdlib
  # into a throwaway jar (~2s), so running every execution case as its own
  # compile dominated the suite. Instead `setup_all` emits ALL the execution
  # cases below into ONE compilation unit — each in its own `package rian_case_N`
  # (so two snippets may both define a top-level `fun f` without colliding) plus
  # a marker-fenced runner `main` — compiles once, runs once, and the per-case
  # stdout is parsed back into `%{id => %{kt, out}}`. One kotlinc for ~20 cases
  # instead of ~20 (ADR-0049 Tier 2; verified via kotlinc + java).
  #
  # The shape assertions (`assert kt =~ …`) are pure `Rian.JVM` checks and run
  # whether or not the toolchain is present; only the executed-output check is
  # gated on `out != :no_jvm`. `setup_all` skips the whole compile when `:jvm` is
  # excluded (the default loop), so the fast inner loop pays nothing for it.
  @exec_cases [
    %{id: :half, src: "def half(x Float64) Float64 := x / 2.0", probe: ~s|println(half(7.0))|},
    %{
      id: :union,
      src: """
      def describe(x Int53 | String) Int53 := case x do
        n Int53 -> n + 1
        s String -> 0
      end
      """,
      probe: ~S|println("${describe(41L)},${describe("hi")}")|
    },
    %{
      id: :any_param,
      src: "def pick(b Bool, x Any, y Any) Any := if b do x else y end",
      probe: ~S|println("${pick(true, 7L, 9L)},${pick(false, "a", "b")}")|
    },
    %{
      id: :sum_union,
      src: """
      type Box := BoxV(Int53)
      type Bag := BagV(Int53)
      def kind(x Box | Bag) Int53 := case x do
        a Box -> 1
        b Bag -> 2
      end
      """,
      probe: ~S|println("${kind(BoxV(5L))},${kind(BagV(9L))}")|
    },
    %{
      id: :fib,
      src: """
      def fib(n Int64) Int64
      def fib(0) := 0
      def fib(1) := 1
      def fib(n) := fib(n - 1) + fib(n - 2)
      """,
      probe: ~s|println(fib(10L))|
    },
    %{
      id: :shadow,
      src: """
      def shadowed(n Int64) Int64
        x := n + 1
        x := x * 10
        x
      end
      """,
      probe: ~s|println(shadowed(1L)); println(shadowed(4L))|
    },
    %{
      id: :rebind,
      src: "def f(n Int64) Int64\n  n := n + 1\n  n * 2\nend",
      probe: ~s|println(f(5L))|
    },
    %{id: :ref_bump, src: "def bump(x ref Int64) Int64 := x + 1", probe: ~s|println(bump(41L))|},
    %{
      id: :selfhost_opt,
      src: File.read!("test/fixtures/rian/opt.rian"),
      probe: """
        println(fold(Mul(Add(Num(2L), Num(3L)), Num(4L))))
        println(fold(Mul(Var("x"), Num(1L))))
      """
    },
    %{
      id: :guard_when,
      src: """
      def classify(n Int64) Int64
      def classify(n) when n > 0 := 1
      def classify(n) := 0
      """,
      probe: ~s|println(classify(5L)); println(classify(-2L))|
    },
    %{
      id: :guard_lit_catchall,
      src: """
      def classify(n Int64) String
      def classify(n) when n < 0 := "negative"
      def classify(0) := "zero"
      def classify(n) := "positive"
      """,
      probe: ~s|println(classify(-3L)); println(classify(0L)); println(classify(8L))|
    },
    %{
      id: :char_pat,
      src: """
      def kind(c Char) Int64
      def kind('a') := 1
      def kind(c) := 0
      """,
      probe: ~s|println(kind(97L)); println(kind(98L))|
    },
    %{
      id: :if_block,
      src: "def step(n Int64) Int64 := if n > 0 do a := n * 2; a + 1 else 0 end",
      probe: ~s|println(step(3L)); println(step(-1L))|
    },
    %{
      id: :const_ref,
      src: "mod M do\n  const Answer := 42\n  def get() Int53 := Answer\nend",
      probe: ~s|println(get())|
    },
    %{
      id: :const_block,
      src: "mod M do\n  const X := a := 40; a + 2\n  def get() Int53 := X\nend",
      probe: ~s|println(get())|
    },
    %{
      id: :str_pat,
      src: """
      def tag(s String) Int64
      def tag("x") := 1
      def tag(s) := 0
      """,
      probe: ~s|println(tag("x")); println(tag("y"))|
    },
    %{
      id: :str_escape_tqd,
      src: ~S|def s() String := "\t\"$\a"|,
      probe: ~S|println(s().map { it.code }.joinToString(","))|
    },
    %{
      id: :str_escape_bsnl,
      src: ~S|def s() String := "a\\b\nc\rd"|,
      probe: ~S|println(s().map { it.code }.joinToString(","))|
    },
    %{
      id: :list_sum,
      src: """
      def sum(xs Vec(Int64)) Int64
      def sum([]) := 0
      def sum([h | t]) := h + sum(t)
      """,
      probe: ~s|println(sum(listOf(1L, 2L, 3L)))|
    },
    %{
      id: :list_head_lit,
      src: """
      def one(xs Vec(Int64)) String
      def one([1]) := "yes"
      def one(xs) := "no"
      """,
      probe: ~s|println(one(listOf(1L))); println(one(listOf(2L)))|
    },
    %{
      id: :generic_fn,
      src: """
      def first(Vec(T)) T forall T
      def first([h | _]) := h
      def len_l(Vec(T)) Int53 forall T
      def len_l([]) := 0
      def len_l([_ | t]) := 1 + len_l(t)
      """,
      probe: ~s|println(first(listOf("a", "b"))); println(len_l(listOf(1L, 2L, 3L)))|
    },
    %{
      id: :protocol_dispatch,
      src: """
      protocol Eq do
        def eq(a Self, b Self) Bool
      end
      impl Eq for Int53 do
        def eq(a, b) := a == b
      end
      impl Eq for String do
        def eq(a, b) := a == b
      end
      def contains(Vec(T), T) Bool forall T: Eq
      def contains([], _) := false
      def contains([h | t], x) := if eq(h, x) do true else contains(t, x) end
      """,
      probe:
        ~s|println(contains(listOf(1L, 2L, 3L), 2L)); println(contains(listOf("a", "b"), "z"))|
    },
    %{
      id: :foldable_assoc,
      src: """
      protocol Foldable do
        type Elem
        def to_list(self Self) Vec(Elem)
      end
      type Bag := Bag(items Vec(Int53))
      type Words := Words(items Vec(String))
      impl Foldable for Bag do
        type Elem := Int53
        def to_list(b) := case b do Bag(xs) -> xs end
      end
      impl Foldable for Words do
        type Elem := String
        def to_list(w) := case w do Words(ss) -> ss end
      end
      def fcount(x C) Int53 forall C: Foldable := len_l(to_list(x))
      def len_l(Vec(T)) Int53 forall T
      def len_l([]) := 0
      def len_l([_ | t]) := 1 + len_l(t)
      """,
      probe:
        ~s|println(fcount(Bag(listOf(1L, 2L, 3L)))); println(fcount(Words(listOf("a", "b"))))|
    },
    %{
      id: :foldable_typed,
      src: """
      protocol Foldable do
        type Elem
        def to_list(self Self) Vec(Elem)
      end
      type Bag := Bag(items Vec(Int53))
      impl Foldable for Bag do
        type Elem := Int53
        def to_list(b) := case b do Bag(xs) -> xs end
      end
      def sum_l(Vec(Int53)) Int53
      def sum_l([]) := 0
      def sum_l([h | t]) := h + sum_l(t)
      def bag_sum(b Bag) Int53 := sum_l(to_list(b))
      """,
      probe: ~s|println(bag_sum(Bag(listOf(1L, 2L, 3L))))|
    },
    %{
      id: :foldable_bound,
      src: """
      protocol Foldable do
        type Elem
        def to_list(self Self) Vec(Elem)
      end
      type Bag := Bag(items Vec(Int53))
      impl Foldable for Bag do
        type Elem := Int53
        def to_list(b) := case b do Bag(xs) -> xs end
      end
      def sum_l(Vec(Int53)) Int53
      def sum_l([]) := 0
      def sum_l([h | t]) := h + sum_l(t)
      def bag_sum(b Bag) Int53
        xs := to_list(b)
        sum_l(xs)
      end
      """,
      probe: ~s|println(bag_sum(Bag(listOf(1L, 2L, 3L))))|
    },
    %{id: :interp_int, src: ~S|def f(n Int64) String := "v${n}"|, probe: ~S|println(f(42L))|},
    %{
      id: :symbol_tag,
      src: "def tag(s Symbol) Symbol\ndef tag(:ok) := :done\ndef tag(_) := :other\n",
      probe: ~s|println(tag("ok")); println(tag("nope"))|
    },
    %{
      id: :interp_bool,
      src: ~S|def f(b Bool) String := "${b}"|,
      probe: ~S|println(f(true)); println(f(false))|
    },
    %{
      id: :case_sum,
      src: """
      type Shape := Circle(Float64) | Square(Float64)
      def area(s Shape) Float64 := case s do
        Circle(r) -> 3.14159 * r * r
        Square(x) -> x * x
      end
      """,
      probe: ~s|println(area(Circle(2.0))); println(area(Square(3.0)))|
    },
    %{
      id: :case_lit_guard,
      src: """
      def sign(n Int64) String := case n do
        0 -> "zero"
        m when m < 0 -> "neg"
        m -> "pos"
      end
      """,
      probe: ~s|println(sign(0L)); println(sign(-5L)); println(sign(7L))|
    },
    %{
      id: :nested_case,
      src: """
      type Tri := A | B | C
      def nested(x Tri, y Tri) Int64 := case x do
        A -> case y do
          A -> 1
          other -> 2
        end
        rest -> 9
      end
      def bumped(n Int64) Int64 := case n + 1 do
        0 -> 100
        m -> m
      end
      """,
      probe:
        ~s|println(nested(A, A)); println(nested(A, B)); println(nested(B, A)); println(bumped(-1L)); println(bumped(4L))|
    },
    %{
      id: :lambda,
      src: """
      def apply2(f Fn(Int64, Int64), x Int64) Int64 := f(x)
      def adder(n Int64) Fn(Int64, Int64) := (x) -> x + n
      def go(n Int64) Int64 := apply2(adder(n), n)
      """,
      probe: ~s|println(go(20L))|
    },
    %{
      id: :capture,
      src: """
      def apply2(f Fn(Int64, Int64), x Int64) Int64 := f(x)
      def neg(x Int64) Int64 := 0 - x
      def anon(x Int64) Int64 := apply2(&(&1 * 2), x)
      def named(x Int64) Int64 := apply2(&neg/1, x)
      """,
      probe: ~s|println("${anon(5L)},${named(5L)}")|
    },
    %{
      id: :tuple,
      src: """
      def swap(a Int64, b Int64) (Int64, Int64) := {b, a}
      def fst_of(a Int64, b Int64) Int64 := case swap(a, b) do
        {x, y} -> x
      end
      def sum3(a Int64, b Int64, c Int64) Int64 := case {a, b, c} do
        {x, y, z} -> x + y + z
      end
      """,
      probe: ~s|println("${fst_of(1L, 2L)},${sum3(1L, 2L, 3L)}")|
    },
    %{
      id: :membership,
      src: "def has(x Int64, xs Vec(Int64)) Bool := x in xs",
      probe: ~s|println("${has(2L, listOf(1L, 2L, 3L))},${has(9L, listOf(1L, 2L, 3L))}")|
    },
    %{
      id: :struct,
      src: """
      struct Point(x Int64, y Int64)
      def mk(a Int64, b Int64) Point := Point(x: a, y: b)
      def getx(p Point) Int64 := p.x
      def sumxy(p Point) Int64 := case p do
        Point(x: a, y: b) -> a + b
      end
      """,
      probe: ~s|println("${getx(mk(3L, 4L))},${sumxy(mk(3L, 4L))}")|
    },
    %{
      id: :map,
      src: """
      def origin() Dict(Symbol, Int53) := %{x: 1, y: 2}
      def getx(m Dict(Symbol, Int53)) Int53 := Map.get(m, :x)
      def bumped(m Dict(Symbol, Int53)) Int53 := Map.get(Map.put(m, :x, 9), :x)
      def hasx(m Dict(Symbol, Int53)) Bool := Map.has(m, :x)
      """,
      probe: ~s|println("${getx(origin())},${bumped(origin())},${hasx(origin())}")|
    },
    %{
      id: :as_pat,
      src: """
      type Box := Box(Int64)
      def inner(b Box) Int64 := case b do
        whole @ Box(n) -> n
      end
      """,
      probe: ~s|println(inner(Box(7L)))|
    },
    %{
      id: :pin,
      src: """
      def classify(x Int64, target Int64) Int64 := case x do
        ^target -> 1
        _ -> 0
      end
      """,
      probe: ~s|println("${classify(5L, 5L)},${classify(5L, 9L)}")|
    },
    %{
      id: :with,
      src: """
      type Res := Ok(Int64) | Err
      def step(n Int64) Res := if n > 0 do Ok(n + 1) else Err end
      def chain(x Int64) Int64 := with Ok(v) <- step(x), Ok(w) <- step(v) do v + w else Err -> 0 - 1 end
      """,
      probe: ~s|println("${chain(5L)},${chain(-1L)}")|
    }
  ]

  setup_all do
    if jvm_enabled?(), do: %{jvm_batch: run_bundle(@exec_cases)}, else: %{jvm_batch: %{}}
  end

  # `:jvm` tests run iff the tag is not excluded (default loop excludes it) or is
  # explicitly re-included (`mix test --include jvm`, which leaves it in :exclude
  # but adds it to :include — include wins). Only then is the batch worth compiling.
  defp jvm_enabled? do
    cfg = ExUnit.configuration()
    :jvm not in (cfg[:exclude] || []) or :jvm in (cfg[:include] || [])
  end

  # Compile every case's Kotlin (pure, toolchain-free) and, when kotlinc + java
  # are present, execute them all through one bundled jar; otherwise mark the
  # outputs `:no_jvm` so the shape assertions still stand.
  defp run_bundle(cases) do
    kotlinc = System.find_executable("kotlinc")
    java = System.find_executable("java")
    indexed = Enum.with_index(cases)
    kt_by_id = Map.new(cases, fn c -> {c.id, JVM.compile(c.src)} end)

    outs =
      if kotlinc && java,
        do: bundle_outputs(indexed, kt_by_id, kotlinc, java),
        else: Map.new(cases, fn c -> {c.id, :no_jvm} end)

    Map.new(cases, fn c -> {c.id, %{kt: kt_by_id[c.id], out: outs[c.id]}} end)
  end

  # Write one `package`-isolated file per case plus a runner that fences each
  # probe's stdout with `@@S i` / `@@E i` markers and catches per-case runtime
  # errors, compile all in ONE kotlinc, run once, and parse the markers back. A
  # batch compile error (a real regression) falls back to per-case compiles so
  # the failing case is localized rather than failing the whole batch opaquely.
  defp bundle_outputs(indexed, kt_by_id, kotlinc, java) do
    dir = Path.join(System.tmp_dir!(), "rian_jvm_bundle_#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)

    try do
      Enum.each(indexed, fn {c, i} ->
        File.write!(
          Path.join(dir, "case_#{i}.kt"),
          "package rian_case_#{i}\n\n#{kt_by_id[c.id]}\n\nfun __probe() {\n#{c.probe}\n}\n"
        )
      end)

      runner =
        Enum.map_join(indexed, "\n", fn {_c, i} ->
          # Each marker is printed exactly once, on its own line; a per-case
          # runtime throw is caught and reported inline so it can't abort the
          # shared `main` or duplicate a marker.
          ~s|  println("@@S #{i}"); try { rian_case_#{i}.__probe() } | <>
            ~s|catch (e: Throwable) { println("@@ERR " + e) }; println("@@E #{i}")|
        end)

      File.write!(Path.join(dir, "runner.kt"), "fun main() {\n#{runner}\n}\n")
      jar = Path.join(dir, "bundle.jar")
      files = Path.wildcard(Path.join(dir, "*.kt"))

      case System.cmd(kotlinc, files ++ ["-include-runtime", "-d", jar], stderr_to_stdout: true) do
        {_, 0} ->
          {out, 0} = System.cmd(java, ["-jar", jar])
          parse_markers(indexed, out)

        {_err, _code} ->
          per_case_outputs(indexed, kt_by_id, kotlinc, java)
      end
    after
      File.rm_rf!(dir)
    end
  end

  defp parse_markers(indexed, out) do
    Map.new(indexed, fn {c, i} ->
      # Markers are matched line-anchored (`^…$`, `/m`) so a probe that happens
      # to print a marker-like substring can't truncate or shift the capture;
      # `/s` lets `.` span the multi-line probe body.
      captured =
        case Regex.run(~r/^@@S #{i}$\n(.*?)\n?^@@E #{i}$/ms, out) do
          [_, body] -> String.trim(body)
          _ -> "<<no output captured for case #{i}>>"
        end

      {c.id, captured}
    end)
  end

  # Fallback for a batch-compile failure: compile + run each case on its own (the
  # pre-batch path) so a regression surfaces against the exact case that broke.
  defp per_case_outputs(indexed, kt_by_id, kotlinc, java) do
    Map.new(indexed, fn {c, _i} -> {c.id, solo_output(kt_by_id[c.id], c.probe, kotlinc, java)} end)
  end

  defp solo_output(kt, probe, kotlinc, java) do
    base = Path.join(System.tmp_dir!(), "rian_jvm_solo_#{System.unique_integer([:positive])}")
    src = base <> ".kt"
    jar = base <> ".jar"
    File.write!(src, kt <> "\n\nfun main() {\n" <> probe <> "\n}\n")

    result =
      case System.cmd(kotlinc, [src, "-include-runtime", "-d", jar], stderr_to_stdout: true) do
        {_, 0} ->
          {out, 0} = System.cmd(java, ["-jar", jar])
          String.trim(out)

        {err, _} ->
          "<<kotlinc failed>>\n" <> err
      end

    File.rm(src)
    File.rm(jar)
    result
  end

  # The emitted Kotlin for a batched case (computed in `setup_all`, present even
  # when the toolchain is absent) — the subject of the shape assertions.
  defp jvm_kt(jvm, id), do: jvm[id].kt

  # Assert a batched case's executed stdout, no-op'ing when the toolchain is absent.
  defp expect_jvm(jvm, id, expected) do
    case jvm[id].out do
      :no_jvm -> :ok
      out -> assert out == expected
    end
  end

  describe "Kotlin/JVM emitter on the typed core IR (ADR-0049 Tier 2 / ADR-0050)" do
    test "a one-liner: Int64 -> Long, single-clause function" do
      kt = JVM.compile("def double(n Int64) Int64 := n * 2")
      assert kt =~ "fun double(a0: Long): Long"
      assert kt =~ "(n * 2L)"
    end

    test "a guarded clause emits a valid `if (cond)`, never an empty `if ()`" do
      # The by-example clauses tour's guard-lowering fix, asserted on the real
      # emitter (was in Rian.TourTest).
      kt =
        JVM.compile("""
        def classify(n Int53) String
        def classify(n) when n < 0 := "negative"
        def classify(0) := "zero"
        def classify(n) := "positive"
        """)

      refute kt =~ "if ()"
      assert kt =~ ~s|run { val n = a0; if ((n < 0L)) { return "negative" } }|
    end

    @tag :jvm
    test "an `Any` parameter maps to Kotlin `Any` and runs (ADR-0034)", %{jvm_batch: jvm} do
      assert jvm_kt(jvm, :any_param) =~ "pick(a0: Boolean, a1: Any, a2: Any): Any"
      expect_jvm(jvm, :any_param, "7,b")
    end

    @tag :jvm
    test "a value union erases to `Any`, narrowed by `is` (ADR-0083 Phase 5)", %{jvm_batch: jvm} do
      kt = jvm_kt(jvm, :union)
      # the union param erases to `Any`; the type-pattern narrows via `is`
      assert kt =~ "describe(a0: Any)"
      assert kt =~ "x is Long"
      assert kt =~ "x is String"
      # describe(41L) -> 42 ; describe("hi") -> 0
      expect_jvm(jvm, :union, "42,0")
    end

    @tag :jvm
    test "a value union of SUM members narrows by `is <sealed interface>` (ADR-0083)", %{
      jvm_batch: jvm
    } do
      kt = jvm_kt(jvm, :sum_union)
      assert kt =~ "x is Box"
      assert kt =~ "x is Bag"
      # kind(BoxV(5L)) -> 1 ; kind(BagV(9L)) -> 2
      expect_jvm(jvm, :sum_union, "1,2")
    end

    test "a type error is caught by the gate, not emitted as malformed Kotlin (parity)" do
      # JVM.compile now runs `Check.gate!` before emitting (parity with the BEAM path).
      assert_raise Rian.Check.Error, fn -> JVM.compile("def f() Int64 := true") end
    end

    test "a not-yet-implemented construct fails early with a clear message (naming the fn)" do
      # the emitter-capability pre-check: a bitstring isn't on the Tier-2 JVM subset
      # (BEAM-only, ADR-0078), so it raises ONE clear error up front (naming `f`)
      # rather than a deep inspect-dump mid-emission (Reach stays architectural).
      err =
        assert_raise JVM.Unsupported, fn ->
          JVM.compile("def f(x Int64) String := <<x>>")
        end

      assert Exception.message(err) =~
               "`f`: a bitstring (BEAM-only, ADR-0078) is not yet supported on :jvm"
    end

    test "an arity-≥4 tuple has no idiomatic Kotlin form and raises a clear error" do
      # Pair/Triple cover 2/3; ≥4 should use a struct. The body type-checks against an
      # opaque nominal return, so the failure is the emitter's, not the return gate.
      err = assert_raise JVM.Unsupported, fn -> JVM.compile("def f() Quad := {1, 2, 3, 4}") end
      assert Exception.message(err) =~ "4-tuple has no Kotlin form"
    end

    @tag :jvm
    test "float `/` lowers to Kotlin Double division (integer `div` stays `/` on Long)", %{
      jvm_batch: jvm
    } do
      kt = jvm_kt(jvm, :half)
      assert kt =~ "fun half(a0: Double): Double"
      assert kt =~ "(x / 2.0)"
      expect_jvm(jvm, :half, "3.5")
    end

    @tag :jvm
    test "a `const` reference resolves to the emitted top-level val", %{jvm_batch: jvm} do
      # before the const-resolution pass this emitted an unresolved identifier;
      # now the const lowers to `val Answer = 42L` and the reference resolves to it.
      kt = jvm_kt(jvm, :const_ref)
      assert kt =~ "val Answer = 42L"
      expect_jvm(jvm, :const_ref, "42")
    end

    @tag :jvm
    test "a multi-statement `const` value lowers to a `run { … }` val", %{jvm_batch: jvm} do
      kt = jvm_kt(jvm, :const_block)
      assert kt =~ "val X = run { val a = 40L; (a + 2L) }"
      expect_jvm(jvm, :const_block, "42")
    end

    @tag :jvm
    test "a multi-clause function lowers to an if-dispatcher with Long literals", %{
      jvm_batch: jvm
    } do
      kt = jvm_kt(jvm, :fib)
      assert kt =~ "if (a0 == 0L)"
      assert kt =~ "if (a0 == 1L)"
      expect_jvm(jvm, :fib, "55")
    end

    @tag :jvm
    test "a lambda lowers to a Kotlin lambda + function type, capturing natively (ADR-0061)", %{
      jvm_batch: jvm
    } do
      kt = jvm_kt(jvm, :lambda)
      # a `Fn(Int64, Int64)` param/return → a Kotlin function type `(Long) -> Long`
      assert kt =~ "a0: (Long) -> Long"
      assert kt =~ "): (Long) -> Long {"
      # the closure captures `n` from the enclosing frame
      assert kt =~ "{ x -> (x + n) }"
      expect_jvm(jvm, :lambda, "40")
    end

    @tag :jvm
    test "captures lower: `&(…)` to a `{ _N -> … }` lambda, `&name/arity` to `::name`", %{
      jvm_batch: jvm
    } do
      kt = jvm_kt(jvm, :capture)
      assert kt =~ "{ _1 -> (_1 * 2L) }"
      assert kt =~ "apply2(::neg, x)"
      expect_jvm(jvm, :capture, "10,-5")
    end

    @tag :jvm
    test "tuples lower to Pair/Triple, destructured via componentN (ADR-0049 Tier 2)", %{
      jvm_batch: jvm
    } do
      kt = jvm_kt(jvm, :tuple)
      assert kt =~ "): Pair<Long, Long> {"
      assert kt =~ "Pair(b, a)"
      assert kt =~ "Triple(a, b, c)"
      assert kt =~ "(__s).component1()"
      expect_jvm(jvm, :tuple, "2,6")
    end

    @tag :jvm
    test "membership `x in xs` lowers to Kotlin's native `in` and runs", %{jvm_batch: jvm} do
      assert jvm_kt(jvm, :membership) =~ "(x in xs)"
      expect_jvm(jvm, :membership, "true,false")
    end

    @tag :jvm
    test "a struct lowers to a Kotlin data class: named-arg ctor, field access, pattern", %{
      jvm_batch: jvm
    } do
      kt = jvm_kt(jvm, :struct)
      assert kt =~ "data class Point(val x: Long, val y: Long)"
      assert kt =~ "Point(x = a, y = b)"
      assert kt =~ "p.x"
      assert kt =~ "p is Point"
      expect_jvm(jvm, :struct, "3,7")
    end

    @tag :jvm
    test "a map lowers to a Kotlin Map: mapOf literal, getValue, +, containsKey", %{
      jvm_batch: jvm
    } do
      kt = jvm_kt(jvm, :map)
      assert kt =~ ~s|mapOf("x" to 1L, "y" to 2L)|
      assert kt =~ ~s|getValue("x")|
      assert kt =~ "Map<String, Long>"
      expect_jvm(jvm, :map, "1,9,true")
    end

    @tag :jvm
    test "an as-pattern `name @ pat` binds the whole value and matches the inner", %{
      jvm_batch: jvm
    } do
      assert jvm_kt(jvm, :as_pat) =~ "val whole ="
      expect_jvm(jvm, :as_pat, "7")
    end

    @tag :jvm
    test "a pin `^x` lowers to an equality test against the pinned value", %{jvm_batch: jvm} do
      assert jvm_kt(jvm, :pin) =~ "== target"
      expect_jvm(jvm, :pin, "1,0")
    end

    @tag :jvm
    test "a `with` expression desugars to nested cases and runs (ADR-0040)", %{jvm_batch: jvm} do
      expect_jvm(jvm, :with, "13,-1")
    end

    @tag :jvm
    test "`:=` shadowing renames to a backtick-quoted fresh `val` (no Kotlin redeclaration)", %{
      jvm_batch: jvm
    } do
      # Kotlin forbids re-declaring a `val` in a scope, and `$`/`@` are illegal in
      # plain identifiers, so a shadow `x := …; x := …` becomes a backtick-quoted
      # fresh name. Shared rename pass: `Rian.Shadow` (ADR-0034).
      kt = jvm_kt(jvm, :shadow)
      assert kt =~ "val x = (n + 1L)"
      assert kt =~ "val `x$1` = (x * 10L)"
      refute kt =~ "val x = (x * 10L)"
      expect_jvm(jvm, :shadow, "20\n50")
    end

    @tag :jvm
    test "a `:=` rebinding a parameter is renamed, not re-declared", %{jvm_batch: jvm} do
      # the param `n` is already bound (`val n = a0`); rebinding it must rename.
      kt = jvm_kt(jvm, :rebind)
      assert kt =~ "val `n$1` = (n + 1L)"
      refute kt =~ "val n = (n + 1L)"
      expect_jvm(jvm, :rebind, "12")
    end

    @tag :jvm
    test "a `ref` param is lowered to value semantics (sound: return-based surface)", %{
      jvm_batch: jvm
    } do
      # `ref` (&mut) has no Kotlin analog; it only ever changed the Rust signature,
      # so JVM emits an ordinary `val` binding. Reach reports `ref` as reaching :jvm,
      # so this MUST compile (not raise), and the cap must not leak into the emitted
      # parameter. Locks the documented value-lowering decision against a future
      # in-place-mutation primitive silently miscompiling here.
      kt = jvm_kt(jvm, :ref_bump)
      assert kt =~ "fun bump(a0: Long): Long"
      assert kt =~ "val x = a0"
      expect_jvm(jvm, :ref_bump, "42")
    end

    test "a sum type lowers to a sealed interface + data classes" do
      kt = JVM.compile("type Color := Red | Green | RGB(Int64, Int64, Int64)")
      assert kt =~ "sealed interface Color"
      assert kt =~ "object Red : Color"
      assert kt =~ "data class RGB(val f0: Long, val f1: Long, val f2: Long) : Color"
    end

    @tag :jvm
    test "the self-hosting optimizer lowers to Kotlin and folds under java (multi-target)", %{
      jvm_batch: jvm
    } do
      kt = jvm_kt(jvm, :selfhost_opt)
      # the Kotlin showcase: sealed hierarchy + smart-cast `is` patterns
      assert kt =~ "sealed interface Expr"
      assert kt =~ "if (a0 is Add)"
      assert kt =~ "if (a0 is Num && a0.f0 == 0L)"
      # (2+3)*4 constant-folds to Num(20); x*1 simplifies to Var("x")
      expect_jvm(jvm, :selfhost_opt, "Num(f0=20)\nVar(f0=x)")
    end

    test "an unsupported construct raises rather than miscompiling" do
      assert_raise JVM.Unsupported, fn ->
        JVM.compile("def f(s String) Vec(Int64) := String.to_charlist(s)")
      end
    end
  end

  describe "JVM jar assembly (rung B, ADR-0062)" do
    @tag :jvm
    test "to_jar produces a runnable jar that runs under java" do
      case {System.find_executable("kotlinc"), System.find_executable("java")} do
        {nil, _} ->
          :ok

        {_, nil} ->
          :ok

        {_, java} ->
          jar =
            Path.join(System.tmp_dir!(), "rian_jartest_#{System.unique_integer([:positive])}.jar")

          {:ok, ^jar} = JVM.to_jar("def answer() Int64 := 6 * 7", jar, main: "answer")
          assert File.exists?(jar)
          {out, 0} = System.cmd(java, ["-jar", jar])
          assert String.trim(out) == "42"
          File.rm(jar)
      end
    end
  end

  describe "clause heads: guards, char patterns, and unsupported patterns" do
    @tag :jvm
    test "a `when` guard lowers to a guarded `if (cond) { return .. }`", %{jvm_batch: jvm} do
      # a guard-only clause (its variable pattern binds but tests nothing) lowers
      # to a scoped `run { val n = a0; if (guard) { return .. } }` — never an
      # invalid empty `if () { .. }`
      kt = jvm_kt(jvm, :guard_when)
      assert kt =~ "run { val n = a0; if ((n > 0L)) { return 1L } }"
      refute kt =~ "if ()"
      expect_jvm(jvm, :guard_when, "1\n0")
    end

    @tag :jvm
    test "a guard-only first clause followed by literal and catch-all clauses runs", %{
      jvm_batch: jvm
    } do
      kt = jvm_kt(jvm, :guard_lit_catchall)
      assert kt =~ ~s|run { val n = a0; if ((n < 0L)) { return "negative" } }|
      assert kt =~ ~s|if (a0 == 0L) { return "zero" }|
      refute kt =~ "if ()"
      expect_jvm(jvm, :guard_lit_catchall, "negative\nzero\npositive")
    end

    @tag :jvm
    test "a char-literal pattern in a clause head matches on the codepoint", %{jvm_batch: jvm} do
      # 'a' is codepoint 97, matched as a `Long` (jvm.ex:157)
      kt = jvm_kt(jvm, :char_pat)
      assert kt =~ "if (a0 == 97L) { return 1L }"
      expect_jvm(jvm, :char_pat, "1\n0")
    end

    @tag :jvm
    test "list/cons clause patterns lower to size guards + index/drop binds and run", %{
      jvm_batch: jvm
    } do
      kt = jvm_kt(jvm, :list_sum)
      # `[]` -> isEmpty; `[h | t]` -> size guard, head index, tail drop
      assert kt =~ "(a0).isEmpty()"
      assert kt =~ "(a0).size >= 1"
      assert kt =~ "val h = (a0)[0]"
      assert kt =~ "val t = (a0).drop(1)"
      expect_jvm(jvm, :list_sum, "6")
    end

    @tag :jvm
    test "a closed list pattern tests exact size and a leading-element literal matches", %{
      jvm_batch: jvm
    } do
      kt = jvm_kt(jvm, :list_head_lit)
      assert kt =~ "(a0).size == 1"
      expect_jvm(jvm, :list_head_lit, "yes\nno")
    end

    test "an arity-≥4 tuple clause pattern (outside the Tier-2 subset) raises" do
      # Pair/Triple cover 2-/3-tuple patterns (destructured via `componentN`); a
      # ≥4 tuple has no idiomatic Kotlin form and raises a clear error.
      err =
        assert_raise JVM.Unsupported, fn ->
          JVM.compile("""
          def fst(p Int64) Int64
          def fst({a, b, c, d}) := a
          """)
        end

      assert Exception.message(err) =~ "4-tuple pattern"
    end
  end

  describe "literal and unary expressions" do
    test "a char-literal expression emits a `Long` codepoint" do
      kt = JVM.compile("def z(n Char) Char := 'z'")
      # 'z' is codepoint 122 (jvm.ex:199)
      assert kt =~ "return 122L"
    end

    test "a string-literal expression emits a quoted Kotlin string" do
      kt = JVM.compile(~s|def greet(n Int64) String := "hi"|)
      # (jvm.ex:200)
      assert kt =~ ~s|return "hi"|
    end

    test "boolean literals pass through as `true`/`false`" do
      kt = JVM.compile("def yes(n Int64) Bool := true")
      # (jvm.ex:201)
      assert kt =~ "return true"
    end

    test "unary negation emits `-x`" do
      kt = JVM.compile("def neg(x Int64) Int64 := -x")
      # (jvm.ex:204)
      assert kt =~ "return -x"
    end

    test "logical `not` emits `!x`" do
      kt = JVM.compile("def flip(x Bool) Bool := not x")
      # (jvm.ex:205)
      assert kt =~ "return !x"
    end
  end

  describe "if-expressions and blocks" do
    @tag :jvm
    test "an if-expression with a block then-branch emits `run { .. }`", %{jvm_batch: jvm} do
      # the if-expression itself (jvm.ex:216), a multi-statement block branch
      # (jvm.ex:221 -> block_value -> stmt_kt :bind jvm.ex:190 + stmt_value jvm.ex:193),
      # and a bare-expression else-branch (jvm.ex:222)
      kt = jvm_kt(jvm, :if_block)
      assert kt =~ "if ((n > 0L)) run { val a = (n * 2L); (a + 1L) } else 0L"
      expect_jvm(jvm, :if_block, "7\n0")
    end

    test "a single-expression if-branch needs no `run` wrapper" do
      kt = JVM.compile("def sign(n Int64) Int64 := if n >= 0 do 1 else -1 end")
      # both branches are single-expr blocks (jvm.ex:220)
      assert kt =~ "if ((n >= 0L)) 1L else -1L"
    end

    test "a typed bind inside a block emits a `val`" do
      kt = JVM.compile("def st(n Int64) Int64 := if n > 0 do a Int64 := 100; n + a else 0 end")
      # the typed_bind statement (jvm.ex:191)
      assert kt =~ "run { val a = 100L; (n + a) }"
    end

    test "a statement-expression inside a block is emitted then discarded" do
      kt = JVM.compile("def se(n Int64) Int64 := if n > 0 do n + 1; n * 2 else 0 end")
      # a bare-expr statement (jvm.ex:192), with the final expr as the value (jvm.ex:193)
      assert kt =~ "run { (n + 1L); (n * 2L) }"
    end
  end

  describe "operators" do
    test "comparison, equality, logical, concat and rem map to Kotlin operators" do
      kt =
        JVM.compile("""
        def both(a Int64, b Int64) Bool := (a == b) and (a != b) or (a < b)
        """)

      # ==, !=, and->&&, or->|| (jvm.ex:233-236)
      assert kt =~ "(((a == b) && (a != b)) || (a < b))"
    end

    test "string `<>` lowers to Kotlin `+`" do
      kt = JVM.compile(~s|def cat(a String, b String) String := a <> b|)
      # (jvm.ex:237)
      assert kt =~ "return (a + b)"
    end

    test "`rem` lowers to Kotlin `%`" do
      kt = JVM.compile("def md(a Int64, b Int64) Int64 := a rem b")
      # (jvm.ex:240)
      assert kt =~ "return (a % b)"
    end
  end

  describe "type lowering" do
    test "an unknown (lowercase) type annotation raises" do
      # a lowercase, non-builtin type reaches the `kt_type` fall-through. The body is
      # `n` (typed `widget` from the param) so the type gate — now run by
      # `JVM.compile` — passes conservatively, leaving `kt_type` to reject the type.
      assert_raise JVM.Unsupported, fn ->
        JVM.compile("def lc(n widget) widget := n")
      end
    end
  end

  describe "string-literal clause-head patterns (lit_kt binary)" do
    @tag :jvm
    test "a string-literal pattern matches by equality on the Kotlin String", %{jvm_batch: jvm} do
      # a binary literal in a pattern reaches lit_kt/1 binary clause (jvm.ex:273)
      kt = jvm_kt(jvm, :str_pat)
      assert kt =~ ~s|if (a0 == "x")|
      expect_jvm(jvm, :str_pat, "1\n0")
    end
  end

  describe "JVM library jar (to_jar with no :main)" do
    @tag :jvm
    test "to_jar without a :main opt assembles a plain library jar" do
      # kotlin_module(src, nil) = plain compile() — no generated `fun main`
      # (jvm.ex:87/113). Skip the actual kotlinc run when the toolchain is absent,
      # like the runnable-jar test above.
      case System.find_executable("kotlinc") do
        nil ->
          :ok

        _ ->
          jar =
            Path.join(System.tmp_dir!(), "rian_libjar_#{System.unique_integer([:positive])}.jar")

          {:ok, ^jar} = JVM.to_jar("def answer() Int64 := 6 * 7", jar)
          assert File.exists?(jar)
          File.rm(jar)
      end
    end
  end

  describe "string-literal escaping (full Elixir/Gleam set)" do
    @tag :jvm
    test "quotes, control chars and `$` emit a valid, runnable Kotlin literal", %{jvm_batch: jvm} do
      kt = jvm_kt(jvm, :str_escape_tqd)
      assert kt =~ ~S|"\t\"\$\u0007"|
      expect_jvm(jvm, :str_escape_tqd, "9,34,36,7")
    end

    @tag :jvm
    test "backslash, newline and carriage-return escape to `\\\\`, `\\n`, `\\r`", %{
      jvm_batch: jvm
    } do
      # exercises kt_str_cp/1 for ?\\, ?\n, ?\r (jvm.ex:375/378/379) — distinct
      # from the \t/\"/$ test above. A literal backslash doubles; LF/CR become
      # the two-char Kotlin escapes (not the \uHHHH control fallback).
      kt = jvm_kt(jvm, :str_escape_bsnl)
      assert kt =~ ~S|"a\\b\nc\rd"|
      # 'a'=97 '\'=92 'b'=98 '\n'=10 'c'=99 '\r'=13 'd'=100
      expect_jvm(jvm, :str_escape_bsnl, "97,92,98,10,99,13,100")
    end
  end

  describe "string interpolation (ADR-0069) — integer and bool holes" do
    @tag :jvm
    test "an Int64 hole lowers via `(n).toString()` and concatenation", %{jvm_batch: jvm} do
      # `"${n}"` rewrites (Rian.Interp) to a stringify/join chain; the Int64 hole
      # uses `__prim_int_to_string`, which the JVM emitter lowers to Kotlin
      # `(<expr>).toString()` (jvm.ex:345).
      kt = jvm_kt(jvm, :interp_int)
      assert kt =~ "(n).toString()"
      expect_jvm(jvm, :interp_int, "v42")
    end

    @tag :jvm
    test "a Bool hole rewrites to a single-expr-block `if` (branch_kt block path)", %{
      jvm_batch: jvm
    } do
      # `"${b}"` with a Bool hole rewrites (Rian.Interp) to `if (b) "true" else
      # "false"`; each branch is a single-expression `EBlock`, lowered through
      # `branch_kt(%EBlock{stmts: [{:expr, e}]})` (jvm.ex:359).
      kt = jvm_kt(jvm, :interp_bool)
      assert kt =~ ~S|if (b) "true" else "false"|
      expect_jvm(jvm, :interp_bool, "true\nfalse")
    end

    @tag :jvm
    test "an element-TYPED consumer casts the erased dispatcher result `as List<T>` (ADR-0074)",
         %{
           jvm_batch: jvm
         } do
      # `sum_l` takes a concrete `Vec(Int53)` = `List<Long>`, but `to_list(b)` is the
      # erased dispatcher (`List<Any>`). The coercion pass inserts `as List<Long>` so it
      # type-checks; `bag_sum(Bag([1,2,3]))` sums to 6.
      kt = jvm_kt(jvm, :foldable_typed)
      assert kt =~ "sum_l((to_list(b) as List<Long>))"
      expect_jvm(jvm, :foldable_typed, "6")
    end

    @tag :jvm
    test "the cast follows a BOUND erased result into a typed consumer (ADR-0074)", %{
      jvm_batch: jvm
    } do
      # binding the erased dispatcher first (`xs := to_list(b)`) must still cast at the
      # typed use (`sum_l(xs)`) — otherwise `xs : List<Any>` flows into `List<Long>`
      # uncast and kotlinc rejects it, while Reach claims `:jvm` (the honesty gap this
      # closes). The coercion pass flow-tracks `xs` through the bind.
      kt = jvm_kt(jvm, :foldable_bound)
      assert kt =~ "sum_l((xs as List<Long>))"
      expect_jvm(jvm, :foldable_bound, "6")
    end

    @tag :jvm
    test "an associated-type protocol (Foldable) reaches :jvm — `List<Any>` erasure (ADR-0074)",
         %{
           jvm_batch: jvm
         } do
      # `Elem := Int53`/`String` is resolved at expansion (W1) so the impls type-check;
      # the dispatcher's covariant `Vec(Elem)` return erases to `List<Any>`. One `fcount`
      # reduces a `Bag` of `Int53` AND a `Words` of `String` — element-agnostic, runs.
      kt = jvm_kt(jvm, :foldable_assoc)
      assert kt =~ "fun to_list(a0: Any): List<Any> = when (a0) {"
      assert kt =~ "is Bag -> impl_foldable_bag_to_list(a0)"
      expect_jvm(jvm, :foldable_assoc, "3\n2")
    end

    @tag :jvm
    test "a protocol dispatcher lowers to `when (a0)` over `is <Type>` and runs (ADR-0042)", %{
      jvm_batch: jvm
    } do
      # the `eq/2` dispatcher selects an impl by the receiver's runtime type; the
      # bounded-generic consumer `contains forall T: Eq` calls it. Verified end-to-end.
      kt = jvm_kt(jvm, :protocol_dispatch)
      assert kt =~ "fun eq(a0: Any, a1: Any): Boolean = when (a0) {"
      assert kt =~ "is Long -> impl_eq_int53_eq(a0, a1 as Long)"
      assert kt =~ ~S|is String -> impl_eq_string_eq(a0, a1 as String)|
      expect_jvm(jvm, :protocol_dispatch, "true\nfalse")
    end

    @tag :jvm
    test "a generic function (`forall T`) declares Kotlin generics and runs (ADR-0042)", %{
      jvm_batch: jvm
    } do
      # `forall T` lowers to a `<T>` declaration on the function; without it `T` in the
      # signature is an unresolved Kotlin reference (a `:jvm` reach lie before this).
      kt = jvm_kt(jvm, :generic_fn)
      assert kt =~ "fun <T : Any> first(a0: List<T>): T"
      assert kt =~ "fun <T : Any> len_l(a0: List<T>): Long"
      expect_jvm(jvm, :generic_fn, "a\n3")
    end

    @tag :jvm
    test "a `Symbol` lowers to a Kotlin `String` — value, pattern, and param/return (ADR-0041)",
         %{
           jvm_batch: jvm
         } do
      # `:foo` is an interned-name string off the BEAM: the `Symbol` param/return type
      # is `String`, the `:ok` pattern tests `a0 == "ok"`, and the `:done`/`:other`
      # values are string literals.
      kt = jvm_kt(jvm, :symbol_tag)
      assert kt =~ "fun tag(a0: String): String"
      assert kt =~ ~S|a0 == "ok"|
      assert kt =~ ~S|return "done"|
      expect_jvm(jvm, :symbol_tag, "done\nother")
    end
  end

  describe "case expressions" do
    @tag :jvm
    test "a `case` over a sum lowers to a labelled `run` with smart-cast arms", %{jvm_batch: jvm} do
      kt = jvm_kt(jvm, :case_sum)
      assert kt =~ "run rcase@{"
      assert kt =~ "if (s is Circle) { val r = s.f0; return@rcase ((3.14159 * r) * r) }"
      expect_jvm(jvm, :case_sum, "12.56636\n9.0")
    end

    @tag :jvm
    test "a `case` with literal, guard, and catch-all arms runs", %{jvm_batch: jvm} do
      kt = jvm_kt(jvm, :case_lit_guard)
      assert kt =~ ~s|if (n == 0L) { return@rcase "zero" }|
      # guard-only arm is a scoped run; catch-all closes the case (no trailing throw)
      assert kt =~ ~s|run { val m = n; if ((m < 0L)) { return@rcase "neg" } }|
      refute kt =~ "no clause matched"
      expect_jvm(jvm, :case_lit_guard, "zero\nneg\npos")
    end

    @tag :jvm
    test "nested `case` and a non-variable scrutinee compile and run", %{jvm_batch: jvm} do
      # the scrutinee `n + 1` is bound once; nested `return@rcase` targets the inner run
      kt = jvm_kt(jvm, :nested_case)
      assert kt =~ "val __s = (n + 1L)"
      expect_jvm(jvm, :nested_case, "1\n2\n9\n100\n5")
    end
  end

  describe "@external lowering edge (ADR-0068)" do
    test "an @external fn with no `:jvm` body raises (off :jvm, never a stub)" do
      # an `:ex`-only external is not reachable on :jvm; asking the JVM emitter for
      # it raises ONE clear error rather than emitting a stub (jvm.ex:217).
      err =
        assert_raise JVM.Unsupported, fn ->
          JVM.compile(~S|@external(:ex, ":os.system_time()") pub def now() Int64|)
        end

      assert Exception.message(err) =~ "no `@external(:jvm"
    end
  end
end

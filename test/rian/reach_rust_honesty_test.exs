defmodule Rian.ReachRustHonestyTest do
  @moduledoc """
  Gate-honesty regression (ADR-0049 §5a · ADR-0057 · ADR-0061): `Rian.Reach`'s `:rs`
  claims for the integer-generic stdlib slices match what `Rian.Lower` can emit.

  Both historical Rust-generic gaps are now closed and both slices compile to and run
  on Rust, so Reach claims `:rs` for them:

    * **owned-from-borrowed coercion** (`insert`/`sort`/`maximum`/`get`) — `Rian.Lower`
      clones a returned `&T`, `&`-borrows owned call/element args, and clones elements
      stored into an owned `Vec` (gated on a generic function).
    * **parametric user type** — `type Pair := P(k K, v V)` lowers to `enum Pair<K, V>`;
      a generic function reuses the param names (`Pair<K, V>`, plus any free tvar like
      `has`'s `V`), and a non-generic builder (`sample`/`names`) gets its concrete
      instantiation (`Pair<i64, i64>` / `Pair<String, i64>`) inferred from its body.
    * **associated-type protocol** (`foldable`, ADR-0074) — `type Elem: Clone` on the
      trait, a `.to_vec()`'d borrowed-`Vec`-field return (Gap E+), and a borrowed
      constructor argument (`fcount(Bag([1,2,3]))`) make the `Foldable` impls + reducer
      compile and run on Rust.

  The `@tag :rust` cases tie the matrix to reality: each slice must `rustc --test` green.
  """
  use ExUnit.Case, async: false

  alias Rian.{Decl, Reach, Test}

  defp reach(file),
    do: File.read!("examples/rian/#{file}.rian") |> Decl.parse() |> Reach.analyze()

  # `Reach.entry/2` resolves a bare name against the `"name/arity"`-keyed report
  # (and raises clearly on a miss) — these slices have no overloads.
  defp entry(rep, name), do: Reach.entry(rep, name)

  defp targets(rep, name), do: entry(rep, name).reach |> MapSet.to_list() |> Enum.sort()
  defp blocker_kinds(rep, name), do: entry(rep, name).blockers |> Enum.map(& &1.kind)

  describe "17_stdlib_eq_ord — owned-generic return reaches :rs (ADR-0061)" do
    setup do: {:ok, rep: reach("17_stdlib_eq_ord")}

    test "the owned-generic-return functions reach :rs (the coercion landed)", %{rep: rep} do
      for f <- ~w(insert sort maximum contains eq3) do
        assert :rs in targets(rep, f), "#{f} lowers to Rust and must claim :rs"
        refute :generic in blocker_kinds(rep, f), "#{f} should carry no :generic blocker"
      end
    end

    test "every function in the slice reaches :rs", %{rep: rep} do
      for {name, info} <- rep,
          do: assert(:rs in (info.reach |> MapSet.to_list()), "#{name} should reach :rs")
    end
  end

  describe "18_dict_eq — the parametric `Pair` type reaches :rs (ADR-0061)" do
    setup do: {:ok, rep: reach("18_dict_eq")}

    test "signatures over the parametric `Pair` type reach :rs (enum Pair<K,V> landed)", %{
      rep: rep
    } do
      for f <- ~w(get has put sample names) do
        assert :rs in targets(rep, f), "#{f} lowers over `enum Pair<K,V>` and must claim :rs"
        refute :generic in blocker_kinds(rep, f), "#{f} should carry no :generic blocker"
      end
    end

    test "every @test function reaches :rs", %{rep: rep} do
      for f <- ~w(get_finds_value get_returns_default put_shadows_earlier_key
                  has_present has_absent string_keys_work),
          do: assert(:rs in targets(rep, f), "#{f} should reach :rs")
    end
  end

  describe "prelude_dict — `Map(K,V)` lowers to Rust `HashMap` (ADR-0047)" do
    setup do
      {:ok, src: File.read!("examples/rian/prelude_dict.rian")}
    end

    test "every Dict function reaches :rs (the Map→HashMap lowering landed)", %{src: src} do
      rep = src |> Decl.parse() |> Reach.analyze()

      for {name, info} <- rep,
          do: assert(:rs in (info.reach |> MapSet.to_list()), "#{name} should reach :rs")
    end

    @tag :rust
    test "the emitted Rust compiles under rustc (the matrix is honest)", %{src: src} do
      case System.find_executable("rustc") do
        nil ->
          :ok

        rustc ->
          rust = Rian.Lower.rust_program(Decl.parse(src))
          base = Path.join(System.tmp_dir!(), "rian_pd_#{System.unique_integer([:positive])}")
          rs = base <> ".rs"
          lib = base <> ".rlib"
          File.write!(rs, rust)

          try do
            {out, code} =
              System.cmd(
                rustc,
                ["--crate-type", "lib", "-A", "warnings", "--edition", "2021", "-o", lib, rs],
                stderr_to_stdout: true
              )

            assert code == 0, "prelude_dict must compile on rustc (Reach claims :rs):\n#{out}"
          after
            File.rm(rs)
            File.rm(lib)
          end
      end
    end
  end

  describe "compound owned-tvar returns reach :rs; Fn params + concrete Fn returns too (ADR-0061)" do
    test "an `Option(T)`-returning generic reaches :rs (payload cloned at construction)" do
      rep =
        reach_src(
          "def first(xs Vec(T)) Option(T) forall T\ndef first([]) := None\ndef first([h | t]) := Some(h)"
        )

      assert :rs in targets(rep, "first")
    end

    test "a `T | E`-returning generic reaches :rs (the Ok payload is cloned)" do
      rep =
        reach_src("type E := Bad\ndef ok1(x T) Result(T, E) forall T := {:ok, x}")

      assert :rs in targets(rep, "ok1")
    end

    test "a user sum over a tvar reaches :rs" do
      rep = reach_src("type Box := B(v T)\ndef boxit(x T) Box forall T := B(x)")
      assert :rs in targets(rep, "boxit")
    end

    test "an `Fn(...)`-returning generic (a closure over a tvar) NOW reaches :rs — owned capture + `T: Clone + 'static` + per-call clone (ADR-0061)" do
      rep = reach_src("def mk(x T) Fn(Int53, T) forall T := (n) -> x")
      assert :rs in targets(rep, "mk")
    end

    test "an `Fn(...)` *nested* in the return type NOW reaches :rs too — boxed at the value-position closure (ADR-0061)" do
      rep = reach_src("def mk(x T) Option(Fn(Int53, T)) forall T := Some((n) -> x)")
      assert :rs in targets(rep, "mk")
    end

    test "a *concrete* `Fn(...)` return (no tvar) NOW reaches :rs — `Box<dyn Fn>` + `Box::new(move …)` (ADR-0061)" do
      rep = reach_src("def adder(n Int53) Fn(Int53, Int53) := (x) -> x + n")
      assert :rs in targets(rep, "adder")
    end

    test "an `Fn(...)` *parameter* NOW reaches :rs (concrete and generic) — `&impl Fn` (ADR-0061)" do
      conc = reach_src("def apply_twice(f Fn(Int53, Int53), x Int53) Int53 := f(f(x))")
      assert :rs in targets(conc, "apply_twice")

      gen =
        reach_src(
          "def map(f Fn(T, U), xs Vec(T)) Vec(U) forall T, U\ndef map(_, []) := []\ndef map(f, [h | t]) := [f(h) | map(f, t)]"
        )

      assert :rs in targets(gen, "map")
    end

    test "an owned-tvar payload reached via a `:=` binding still reaches :rs (binder cloned)" do
      rep =
        reach_src("def wrap(x T) Option(T) forall T\n  y := x\n  Some(y)\nend")

      assert :rs in targets(rep, "wrap")
    end

    test "a nested-generic owned-tvar return (`Vec(Option(T))`) reaches :rs" do
      rep = reach_src("def wrap(x T) Vec(Option(T)) forall T := [Some(x)]")
      assert :rs in targets(rep, "wrap")
    end

    # The widened :rs claims are load-bearing: these shapes — a `:=`-indirected
    # payload and a nested-generic return — were over-claimed before (rustc rejected
    # the emitted Rust). Compile the emitted Rust to prove the matrix is now honest.
    @tag :rust
    test "the binding-indirected and nested-generic returns genuinely compile on rustc" do
      case System.find_executable("rustc") do
        nil ->
          :ok

        rustc ->
          for src <- [
                "def wrap(x T) Option(T) forall T\n  y := x\n  Some(y)\nend",
                "def wrap(x T) Vec(Option(T)) forall T := [Some(x)]",
                "type E := Bad\ndef ok1(x T) Result(T, E) forall T\n  y := x\n  {:ok, y}\nend",
                # a primitive value-union PARAMETER (ADR-0083 Phase 4): the synthesized
                # `enum` + `From` + `match` narrowing + call-site `::from` construction
                "def describe(x Int53 | String) Int53 := case x do\n  n Int53 -> n + 1\n  s String -> 0\nend\ndef caller() Int53 := describe(41)",
                # a value union of SUM members (the enum wraps user enums; ADR-0083)
                "type Box := BoxV(Int53)\ntype Bag := BagV(Int53)\ndef kind(x Box | Bag) Int53 := case x do\n  a Box -> 1\n  b Bag -> 2\nend\ndef cb() Int53 := kind(BoxV(5))",
                # a value-union RETURN: each member-producing tail leaf wraps via
                # `Enum::from`, pushed into the `if` branches (ADR-0083)
                "def mk(b Bool) Int53 | String := if b do 1 else 33 end",
                # a non-param union SCRUTINEE: a `case` over a union binding AND a
                # union-returning call narrow to the synthesized `enum` (ADR-0083)
                "def mk(b Bool) Int53 | String := if b do 1 else 33 end\ndef viaBind(b Bool) Int53\n  x := mk(b)\n  case x do\n    n Int53 -> n\n    s String -> 0\n  end\nend\ndef viaCall(b Bool) Int53 := case mk(b) do\n  n Int53 -> n\n  s String -> 0\nend"
              ] do
            rust = Rian.Lower.rust_program(Decl.parse(src))
            base = Path.join(System.tmp_dir!(), "rian_pos_#{System.unique_integer([:positive])}")
            f = base <> ".rs"
            out_lib = base <> ".rlib"
            File.write!(f, rust)

            try do
              # -o keeps the .rlib in tmp; without it `--crate-type lib` writes to cwd.
              {out, code} =
                System.cmd(
                  rustc,
                  [
                    "--crate-type",
                    "lib",
                    "-A",
                    "warnings",
                    "--edition",
                    "2021",
                    "-o",
                    out_lib,
                    f
                  ],
                  stderr_to_stdout: true
                )

              assert code == 0, "Reach claims :rs, so the emitted Rust must compile:\n#{out}"
            after
              File.rm(f)
              File.rm(out_lib)
            end
          end
      end
    end

    # Closure-as-value lowering (ADR-0061): a `Fn(...)` parameter (`&impl Fn`, called +
    # re-passed in recursion), a multi-use element (`filter`), a multi-arg + borrowed-acc
    # closure call (`reduce`), and a concrete returned closure (`adder` → `Box::new(move …)`)
    # must all compile AND run on rustc — the matrix now claims them `:rs`.
    @tag :rust
    test "Fn-param HOF and a concrete returned closure compile and run on rustc" do
      case System.find_executable("rustc") do
        nil ->
          :ok

        rustc ->
          src = """
          mod M do
            pub def map(xs Vec(T), f Fn(T, U)) Vec(U) forall T, U
            pub def map([], _) := []
            pub def map([h | t], f) := [f(h) | map(t, f)]

            pub def filter(xs Vec(T), f Fn(T, Bool)) Vec(T) forall T
            pub def filter([], _) := []
            pub def filter([h | t], f) := if f(h) do [h | filter(t, f)] else filter(t, f) end

            pub def reduce(xs Vec(T), acc U, f Fn(T, U, U)) U forall T, U
            pub def reduce([], acc, _) := acc
            pub def reduce([h | t], acc, f) := reduce(t, f(h, acc), f)

            pub def adder(n Int53) Fn(Int53, Int53) := (x) -> x + n
          end
          """

          rust = Rian.Lower.rust_program(Decl.parse(src))

          main = """
          fn main() {
            assert_eq!(m::map(&vec![1i64,2,3], &|x| x + 1), vec![2,3,4]);
            assert_eq!(m::filter(&vec![1i64,2,3,4], &|x| x % 2 == 0), vec![2,4]);
            assert_eq!(m::reduce(&vec![1i64,2,3], &0, &|x, acc| x + acc), 6);
            assert_eq!(m::adder(10)(5), 15);
            println!("ok");
          }
          """

          base = Path.join(System.tmp_dir!(), "rian_fn_#{System.unique_integer([:positive])}")
          f = base <> ".rs"
          bin = base
          File.write!(f, rust <> "\n" <> main)

          try do
            {out, code} =
              System.cmd(rustc, ["-A", "warnings", "--edition", "2021", "-o", bin, f],
                stderr_to_stdout: true
              )

            assert code == 0, "Fn lowering must compile on rustc:\n#{out}"
            assert {"ok\n", 0} = System.cmd(bin, [])
          after
            File.rm(f)
            File.rm(bin)
          end
      end
    end
  end

  defp reach_src(src), do: Decl.parse(src) |> Reach.analyze()

  describe "parametric shapes beyond the emitter's monomorphic subset are pinned off :rs" do
    # The `enum Pair<K,V>` support is narrow: the Reach matrix must pin off `:rs`
    # every parametric shape `Rian.Lower` cannot monomorphize, or `mix rian.targets`
    # green-lights code rustc rejects (ADR-0061). Each case below emits broken Rust.
    defp analyze(src), do: src |> Decl.parse() |> Reach.analyze()

    test "F2: a `Vec`/`Option` tvar field NOW reaches :rs (the enum declares its generics)" do
      rep = analyze("type Box := B(items Vec(T))\ndef wrap(x T) Box forall T := B([x])")
      assert :rs in targets(rep, "wrap")
    end

    test "F2: a `Dict`/`Fn` tvar field is STILL pinned off :rs (separate lowering gaps)" do
      dict = analyze("type Map := M(d Dict(K, V))\ndef mk(d Dict(K, V)) Map forall K, V := M(d)")
      refute :rs in targets(dict, "mk")
      assert :generic in blocker_kinds(dict, "mk")

      fnf = analyze("type Cell := C(f Fn(Int53, T))\ndef mk(x T) Cell forall T := C((n) -> x)")
      refute :rs in targets(fnf, "mk")
    end

    test "F2: a parametric type nesting another parametric type NOW reaches :rs (direct + chain)" do
      direct =
        analyze(
          "type Pair := P(k K, v V)\ntype Wrap := W(p Pair)\ndef mk(k K, v V) Wrap forall K, V := W(P(k, v))"
        )

      assert :rs in targets(direct, "mk")

      chain =
        analyze(
          "type Pair := P(k K, v V)\ntype Mid := M(p Pair)\ntype Out := O(m Mid)\ndef mk(k K, v V) Out forall K, V := O(M(P(k, v)))"
        )

      assert :rs in targets(chain, "mk")
    end

    test "F2: a recursion CYCLE or a parametric type nested in a compound STAYS pinned (needs Box / no args surfaced)" do
      # self-recursion is an infinitely-sized Rust type (would need `Box`) — the monotone
      # emittability fixpoint never bootstraps it, so it stays off :rs.
      rec =
        analyze(
          "type Tree := Leaf(v T) | Node(l Tree, r Tree)\ndef leaf(x T) Tree forall T := Leaf(x)"
        )

      refute :rs in targets(rec, "leaf")

      # a parametric type inside a compound (`Vec(Pair)`) surfaces no args → `Vec<Pair>` is
      # an undeclared generic; the enclosing `Bag` is gated parametric and pinned.
      bag =
        analyze(
          "type Pair := P(k K, v V)\ntype Bag := B(ps Vec(Pair))\ndef mk(ps Vec(Pair)) Bag forall K, V := B(ps)"
        )

      refute :rs in targets(bag, "mk")
    end

    test "F3: a generic builder whose construction args don't match the field tvars" do
      rep =
        analyze("type Pair := P(k K, v V)\ndef mk(a A, b B) Pair forall A, B := P(a, b)")

      refute :rs in targets(rep, "mk")
      assert :generic in blocker_kinds(rep, "mk")
    end

    test "F1: a non-generic builder that can't infer its concrete instantiation" do
      src = """
      type Pair := P(k K, v V)
      def put(d Vec(Pair), key K, value V) Vec(Pair) forall K, V := [P(key, value) | d]
      def names(flag Bool) Vec(Pair) := if flag do put([], 1, 10) else put([], 2, 20) end
      def direct() Vec(Pair) := [P(1, 2)]
      """

      rep = analyze(src)
      # the aligned generic constructor `put` stays on :rs; the two builders don't.
      assert :rs in targets(rep, "put")
      refute :rs in targets(rep, "names")
      refute :rs in targets(rep, "direct")
    end

    # Honesty in both directions: the shape Reach now pins off :rs genuinely fails
    # rustc, so the blocker is load-bearing, not a guess.
    @tag :rust
    test "the pinned-off shape genuinely does not compile on rustc" do
      case System.find_executable("rustc") do
        nil ->
          :ok

        rustc ->
          # a `Dict` tvar field is still pinned (no `HashMap` mapping in this position) — its
          # emitted `Dict<K, V>` is not a Rust type, so rustc rejects it (the blocker is real).
          rust =
            Test.rust("type Map := M(d Dict(K, V))\ndef mk(d Dict(K, V)) Map forall K, V := M(d)")

          base = Path.join(System.tmp_dir!(), "rian_neg_#{System.unique_integer([:positive])}")
          src = base <> ".rs"
          out_lib = base <> ".rlib"
          File.write!(src, rust)

          try do
            # -o keeps any output in tmp; without it `--crate-type lib` writes to cwd.
            {_out, code} =
              System.cmd(
                rustc,
                [
                  "--crate-type",
                  "lib",
                  "-A",
                  "warnings",
                  "--edition",
                  "2021",
                  "-o",
                  out_lib,
                  src
                ],
                stderr_to_stdout: true
              )

            refute code == 0,
                   "the Dict(K,V)-field shape must NOT compile (Reach is right to pin it)"
          after
            File.rm(src)
            File.rm(out_lib)
          end
      end
    end
  end

  # The :rs claims are justified — rustc compiles AND runs each slice's `@test`s.
  @tag :rust
  test "rustc compiles and runs the @tests of both Rust-portable stdlib slices" do
    case System.find_executable("rustc") do
      nil ->
        :ok

      rustc ->
        for file <- ~w(17_stdlib_eq_ord 18_dict_eq) do
          src = Path.join(System.tmp_dir!(), "rian_h_#{System.unique_integer([:positive])}.rs")
          bin = String.trim_trailing(src, ".rs")
          File.write!(src, Test.rust(File.read!("examples/rian/#{file}.rian")))

          try do
            {out, code} =
              System.cmd(rustc, ["--test", "-A", "warnings", "--edition", "2021", src, "-o", bin],
                stderr_to_stdout: true
              )

            assert code == 0, "#{file} should compile on rustc:\n#{out}"
            {run, rc} = System.cmd(bin, [])
            assert rc == 0, "#{file}'s @tests should pass under rustc --test:\n#{run}"
          after
            File.rm(src)
            File.rm(bin)
          end
        end
    end
  end

  describe "foldable — an associated-type protocol reaches :rs (ADR-0074)" do
    setup do: {:ok, rep: reach("foldable")}

    test "the Foldable impls reach :rs (a borrowed `&Vec` field return is `.to_vec()`d)", %{
      rep: rep
    } do
      # `def to_list(b) := case b do Bag(xs) -> xs end` binds `xs` to a `&Vec<T>`; the
      # `-> Vec<T>` method clones it (Gap E+). Before that coercion these impls claimed
      # `:rs` but rustc rejected the emitted `=> xs` (E0308) — an uncaught matrix lie.
      for f <- ~w(impl_foldable_bag_to_list impl_foldable_words_to_list) do
        assert :rs in targets(rep, f),
               "#{f} returns a borrowed Vec field — must clone + claim :rs"
      end
    end
  end

  @tag :rust
  test "rustc compiles+runs `fcount` over an associated-type Foldable (sum + `Vec(Elem)` return)" do
    case System.find_executable("rustc") do
      nil ->
        :ok

      rustc ->
        # The element-agnostic reducer over a one-method protocol with an associated
        # `type Elem` (ADR-0074): one `fcount` reduces both a `Bag` of `Int53` AND a
        # `Words` of `String`, exercising every coercion that had to land — the `&Vec`
        # field return is `.to_vec()`d, the trait carries `type Elem: Clone`, the
        # `fcount(Bag(...))` call borrows the constructed argument, and the `Words` value
        # builds its `Vec(String)` field from string literals via `.to_string()`.
        prog = """
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

        @test def counts_a_bag() Bool := fcount(Bag([1, 2, 3])) == 3
        @test def counts_words() Bool := fcount(Words(["a", "b"])) == 2
        """

        src = Path.join(System.tmp_dir!(), "rian_fold_#{System.unique_integer([:positive])}.rs")
        bin = String.trim_trailing(src, ".rs")
        File.write!(src, Test.rust(prog))

        try do
          {out, code} =
            System.cmd(rustc, ["--test", "-A", "warnings", "--edition", "2021", src, "-o", bin],
              stderr_to_stdout: true
            )

          assert code == 0, "the associated-type Foldable should compile on rustc:\n#{out}"
          {run, rc} = System.cmd(bin, [])
          assert rc == 0, "fcount's @tests should pass under rustc --test:\n#{run}"
        after
          File.rm(src)
          File.rm(bin)
        end
    end
  end

  @tag :rust
  test "rustc compiles+runs an `Option(T)` / `T | E` generic return (compound owned-tvar)" do
    case System.find_executable("rustc") do
      nil ->
        :ok

      rustc ->
        prog = """
        type E := Bad

        def first(xs Vec(T)) Option(T) forall T
        def first([]) := None
        def first([h | t]) := Some(h)

        def ok1(x T) Result(T, E) forall T := {:ok, x}

        @test def first_some() Bool
          case first([7, 8, 9]) do
            Some(x) -> x == 7
            None -> false
          end
        end

        @test def ok_wraps() Bool
          case ok1(5) do
            {:ok, v} -> v == 5
            {:error, _} -> false
          end
        end
        """

        src = Path.join(System.tmp_dir!(), "rian_ct_#{System.unique_integer([:positive])}.rs")
        bin = String.trim_trailing(src, ".rs")
        File.write!(src, Test.rust(prog))

        try do
          {out, code} =
            System.cmd(rustc, ["--test", "-A", "warnings", "--edition", "2021", src, "-o", bin],
              stderr_to_stdout: true
            )

          assert code == 0, "compound-tvar returns should compile on rustc:\n#{out}"
          {_run, rc} = System.cmd(bin, [])
          assert rc == 0, "the @tests should pass under rustc --test"
        after
          File.rm(src)
          File.rm(bin)
        end
    end
  end
end

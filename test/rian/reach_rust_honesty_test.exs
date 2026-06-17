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

  The `@tag :rust` cases tie the matrix to reality: both slices must `rustc --test` green.
  """
  use ExUnit.Case, async: false

  alias Rian.{Decl, Reach, Test}

  defp reach(file),
    do: File.read!("examples/rian/#{file}.rian") |> Decl.parse() |> Reach.analyze()

  defp targets(rep, name), do: rep[name].reach |> MapSet.to_list() |> Enum.sort()
  defp blocker_kinds(rep, name), do: rep[name].blockers |> Enum.map(& &1.kind)

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

  describe "compound owned-tvar returns reach :rs; Fn params + concrete Fn returns too (ADR-0061)" do
    test "an `Option(T)`-returning generic reaches :rs (payload cloned at construction)" do
      rep =
        reach_src(
          "def first(xs Vec(T)) Option(T) forall T\ndef first([]) := None\ndef first([h | t]) := Some(h)"
        )

      assert :rs in (rep["first"].reach |> MapSet.to_list())
    end

    test "a `T | E`-returning generic reaches :rs (the Ok payload is cloned)" do
      rep =
        reach_src("type E := Bad\ndef ok1(x T) T | E forall T := {:ok, x}")

      assert :rs in (rep["ok1"].reach |> MapSet.to_list())
    end

    test "a user sum over a tvar reaches :rs" do
      rep = reach_src("type Box := B(v T)\ndef boxit(x T) Box forall T := B(x)")
      assert :rs in (rep["boxit"].reach |> MapSet.to_list())
    end

    test "an `Fn(...)`-returning generic (a closure over a tvar) is still off :rs" do
      rep = reach_src("def mk(x T) Fn(Int53, T) forall T := (n) -> x")
      refute :rs in (rep["mk"].reach |> MapSet.to_list())
      assert :generic in (rep["mk"].blockers |> Enum.map(& &1.kind))
    end

    test "an `Fn(...)` *nested* in the return type is also off :rs (not just a prefix)" do
      rep = reach_src("def mk(x T) Option(Fn(Int53, T)) forall T := Some((n) -> x)")
      refute :rs in (rep["mk"].reach |> MapSet.to_list())
      assert :generic in (rep["mk"].blockers |> Enum.map(& &1.kind))
    end

    test "a *concrete* `Fn(...)` return (no tvar) NOW reaches :rs — `Box<dyn Fn>` + `Box::new(move …)` (ADR-0061)" do
      rep = reach_src("def adder(n Int53) Fn(Int53, Int53) := (x) -> x + n")
      assert :rs in (rep["adder"].reach |> MapSet.to_list())
    end

    test "an `Fn(...)` *parameter* NOW reaches :rs (concrete and generic) — `&impl Fn` (ADR-0061)" do
      conc = reach_src("def apply_twice(f Fn(Int53, Int53), x Int53) Int53 := f(f(x))")
      assert :rs in (conc["apply_twice"].reach |> MapSet.to_list())

      gen =
        reach_src(
          "def map(f Fn(T, U), xs Vec(T)) Vec(U) forall T, U\ndef map(_, []) := []\ndef map(f, [h | t]) := [f(h) | map(f, t)]"
        )

      assert :rs in (gen["map"].reach |> MapSet.to_list())
    end

    test "an owned-tvar payload reached via a `:=` binding still reaches :rs (binder cloned)" do
      rep =
        reach_src("def wrap(x T) Option(T) forall T\n  y := x\n  Some(y)\nend")

      assert :rs in (rep["wrap"].reach |> MapSet.to_list())
    end

    test "a nested-generic owned-tvar return (`Vec(Option(T))`) reaches :rs" do
      rep = reach_src("def wrap(x T) Vec(Option(T)) forall T := [Some(x)]")
      assert :rs in (rep["wrap"].reach |> MapSet.to_list())
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
                "type E := Bad\ndef ok1(x T) T | E forall T\n  y := x\n  {:ok, y}\nend"
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
  end

  defp reach_src(src), do: Decl.parse(src) |> Reach.analyze()

  describe "parametric shapes beyond the emitter's monomorphic subset are pinned off :rs" do
    # The `enum Pair<K,V>` support is narrow: the Reach matrix must pin off `:rs`
    # every parametric shape `Rian.Lower` cannot monomorphize, or `mix rian.targets`
    # green-lights code rustc rejects (ADR-0061). Each case below emits broken Rust.
    defp analyze(src), do: src |> Decl.parse() |> Reach.analyze()

    test "F2: a parametric type with a non-bare-tvar field (Vec(T)) — undeclared generic" do
      rep = analyze("type Box := B(items Vec(T))\ndef wrap(x T) Box forall T := B([x])")
      refute :rs in targets(rep, "wrap")
      assert :generic in blocker_kinds(rep, "wrap")
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
          rust = Test.rust("type Box := B(items Vec(T))\ndef wrap(x T) Box forall T := B([x])")
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

            refute code == 0, "the Vec(T)-field shape must NOT compile (Reach is right to pin it)"
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

        def ok1(x T) T | E forall T := {:ok, x}

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

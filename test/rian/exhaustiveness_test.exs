defmodule Rian.ExhaustivenessTest do
  use ExUnit.Case, async: true
  alias Rian.Exhaustiveness, as: E

  # pattern constructors
  defp w, do: :wild
  defp c(id, args \\ []), do: {:ctor, id, args}
  defp lit(v), do: {:ctor, {:lit, v}, []}
  defp lnil, do: {:ctor, nil, []}
  defp cons(h, t), do: {:ctor, :cons, [h, t]}
  defp arm(pat, guard \\ false), do: %{pat: pat, guard: guard}

  defp env_option, do: E.add_type(E.base_env(), :option, [{:some, 1}, {:none, 0}])
  defp env_shape, do: E.add_type(E.base_env(), :shape, [{:circle, 1}, {:square, 1}])
  defp env_tree, do: E.add_type(E.base_env(), :tree, [{:leaf, 0}, {:node, 3}])
  defp env_bit, do: E.add_range(E.base_env(), :bit, 0, 1)
  defp env_digit, do: E.add_range(E.base_env(), :digit, 0, 9)

  describe "exhaustiveness — finite types" do
    test "bool: both literals are exhaustive" do
      r = E.analyze([arm([c(true)]), arm([c(false)])], 1, E.base_env())
      assert r.exhaustive?
      assert r.missing == nil
    end

    test "bool: missing `false` is reported with a witness" do
      r = E.analyze([arm([c(true)])], 1, E.base_env())
      refute r.exhaustive?
      assert E.render(r.missing) == "false"
    end

    test "option: Some + None is exhaustive" do
      r = E.analyze([arm([c(:some, [w()])]), arm([c(:none)])], 1, env_option())
      assert r.exhaustive?
    end

    test "option: missing None -> witness `None`" do
      r = E.analyze([arm([c(:some, [w()])])], 1, env_option())
      refute r.exhaustive?
      assert E.render(r.missing) == "None"
    end

    test "shape: missing Square -> witness `Square(_)`" do
      r = E.analyze([arm([c(:circle, [w()])])], 1, env_shape())
      refute r.exhaustive?
      assert E.render(r.missing) == "Square(_)"
    end
  end

  describe "lists" do
    test "nil + cons is exhaustive" do
      r = E.analyze([arm([lnil()]), arm([cons(w(), w())])], 1, E.base_env())
      assert r.exhaustive?
    end

    test "only nil -> witness `[_ | _]`" do
      r = E.analyze([arm([lnil()])], 1, E.base_env())
      refute r.exhaustive?
      assert E.render(r.missing) == "[_ | _]"
    end

    test "only cons -> witness `[]`" do
      r = E.analyze([arm([cons(w(), w())])], 1, E.base_env())
      refute r.exhaustive?
      assert E.render(r.missing) == "[]"
    end
  end

  describe "nested constructors" do
    test "Tree with only Leaf and Node(Leaf,_,_) is non-exhaustive (deep witness)" do
      arms = [arm([c(:leaf)]), arm([c(:node, [c(:leaf), w(), w()])])]
      r = E.analyze(arms, 1, env_tree())
      refute r.exhaustive?
      # the uncovered case is a Node whose left child is itself a Node
      assert E.render(r.missing) =~ "Node(Node("
    end

    test "Tree with Leaf and Node(_,_,_) is exhaustive" do
      arms = [arm([c(:leaf)]), arm([c(:node, [w(), w(), w()])])]
      assert E.analyze(arms, 1, env_tree()).exhaustive?
    end
  end

  describe "primitives are infinite — require a wildcard" do
    test "two int literals are NOT exhaustive" do
      r = E.analyze([arm([lit(0)]), arm([lit(1)])], 1, E.base_env())
      refute r.exhaustive?
      assert E.render(r.missing) == "_"
    end

    test "literals plus wildcard ARE exhaustive" do
      r = E.analyze([arm([lit(0)]), arm([lit(1)]), arm([w()])], 1, E.base_env())
      assert r.exhaustive?
    end
  end

  describe "range types are finite — full interval coverage is exhaustive (ADR-0036)" do
    test "Bit (0..1): covering both members is exhaustive with no wildcard" do
      r = E.analyze([arm([lit(0)]), arm([lit(1)])], 1, env_bit())
      assert r.exhaustive?
      assert r.missing == nil
    end

    test "Bit (0..1): missing `1` -> witness `1`" do
      r = E.analyze([arm([lit(0)])], 1, env_bit())
      refute r.exhaustive?
      assert E.render(r.missing) == "1"
    end

    test "Digit (0..9): covering every member is exhaustive" do
      arms = for v <- 0..9, do: arm([lit(v)])
      assert E.analyze(arms, 1, env_digit()).exhaustive?
    end

    test "Digit (0..9): a hole in the interval is reported with the missing member" do
      arms = for v <- 0..9, v != 5, do: arm([lit(v)])
      r = E.analyze(arms, 1, env_digit())
      refute r.exhaustive?
      assert E.render(r.missing) == "5"
    end

    test "a wildcard arm after full interval coverage is unreachable" do
      arms = [arm([lit(0)]), arm([lit(1)]), arm([w()])]
      assert E.analyze(arms, 1, env_bit()).unreachable == [2]
    end

    test "same literal value stays infinite when NOT a range member" do
      # `0`/`1` in the base env are bare Int64 literals — still need a wildcard.
      r = E.analyze([arm([lit(0)]), arm([lit(1)])], 1, E.base_env())
      refute r.exhaustive?
      assert E.render(r.missing) == "_"
    end
  end

  describe "guards do not count toward exhaustiveness" do
    test "a guarded Some(_) leaves the match non-exhaustive" do
      arms = [arm([c(:some, [w()])], true), arm([c(:none)])]
      r = E.analyze(arms, 1, env_option())
      refute r.exhaustive?
      assert E.render(r.missing) == "Some(_)"
    end
  end

  describe "reachability" do
    test "a clause after a wildcard is unreachable" do
      arms = [arm([w()]), arm([c(:leaf)])]
      assert E.analyze(arms, 1, env_tree()).unreachable == [1]
    end

    test "a guarded clause does NOT shadow a later identical clause" do
      arms = [arm([c(:some, [w()])], true), arm([c(:some, [w()])], false)]
      assert E.analyze(arms, 1, env_option()).unreachable == []
    end

    test "an exact duplicate after an unguarded clause is unreachable" do
      arms = [arm([c(:none)]), arm([c(:none)])]
      assert E.analyze(arms, 1, env_option()).unreachable == [1]
    end
  end

  describe "multi-argument clauses (tuple matrix)" do
    test "wildcard fallback row makes a 2-arg match exhaustive" do
      arms = [arm([lit(0), lit(0)]), arm([w(), w()])]
      assert E.analyze(arms, 2, E.base_env()).exhaustive?
    end

    test "single (0,0) clause is non-exhaustive" do
      r = E.analyze([arm([lit(0), lit(0)])], 2, E.base_env())
      refute r.exhaustive?
    end
  end

  describe "tuple-pattern witnesses (rendered as `{a, b}`)" do
    # a tuple constructor `{:tuple, n}` as a single column makes its signature
    # `{:complete, [t]}`; an incomplete sub-pattern leaves a tuple-shaped witness,
    # rendered by `render({:ctor, {:tuple, _}, args})` (exhaustiveness.ex:234).
    test "a tuple pattern with an incomplete bool element -> witness `{false, _}`" do
      arms = [arm([c({:tuple, 2}, [c(true), w()])])]
      r = E.analyze(arms, 1, E.base_env())
      refute r.exhaustive?
      assert E.render(r.missing) == "{false, _}"
    end

    test "render of a fully-wild tuple witness is `{_, _}`" do
      assert E.render(c({:tuple, 2}, [w(), w()])) == "{_, _}"
    end

    test "a tuple pattern over an incomplete sum -> witness names the missing variant" do
      # the inner column is a sum head with only `:some` present, so the witness
      # recursion hits the `:incomplete` branch (exhaustiveness.ex:172) and
      # `missing_head` returns the missing `:none` variant (exhaustiveness.ex:186).
      arms = [arm([c({:tuple, 2}, [c(:some, [w()]), w()])])]
      r = E.analyze(arms, 1, env_option())
      refute r.exhaustive?
      assert E.render(r.missing) == "{None, _}"
    end
  end

  # A non-exhaustive body `case` LOWERS with a runtime fallthrough, the same as a
  # non-total *function* (ADR-0036, 2026-06-20) — it is no longer refused. BEAM raises
  # `case_clause`, JS/JVM `throw`, and the Rust emitter appends a `_ => panic!(…)` arm
  # (`Rian.Lower.resolve_rust_pats`). The usefulness analysis still runs unchanged — it
  # now *informs* the Rust fallthrough instead of gating emission.
  describe "case-expression exhaustiveness (lowers with a runtime fallthrough, ADR-0036)" do
    defp compile_ok?(src) do
      Rian.Decl.compile(src)
      :ok
    rescue
      e in RuntimeError -> {:refused, Exception.message(e)}
    end

    test "a non-exhaustive `case` over a sum type lowers (no longer refused)" do
      assert :ok =
               compile_ok?("type C := A | B\npub def f(c C) Int53 := case c do\n  A -> 1\nend")
    end

    test "the analysis still flags the non-exhaustive `case` (it informs, not gates)" do
      # the arm matrix is still seen as non-total — the change is only that it no
      # longer raises; `B` remains an uncovered row.
      env = E.add_type(E.base_env(), :c, [{:a, 0}, {:b, 0}])
      r = E.analyze([arm([c(:a)])], 1, env)
      refute r.exhaustive?
    end

    test "an exhaustive `case` (all variants, or a `_`) compiles" do
      assert :ok =
               compile_ok?(
                 "type C := A | B\npub def f(c C) Int53 := case c do\n  A -> 1\n  B -> 2\nend"
               )

      assert :ok =
               compile_ok?(
                 "type C := A | B\npub def f(c C) Int53 := case c do\n  A -> 1\n  _ -> 0\nend"
               )
    end

    test "a NESTED non-exhaustive `case` (in an arm body) lowers too" do
      src =
        "type C := A | B\npub def f(x C, c C) Int53 := case x do\n  A -> case c do\n    A -> 1\n  end\n  B -> 2\nend"

      assert :ok = compile_ok?(src)
    end

    test "a non-exhaustive `case` over literals (no `_`) lowers" do
      assert :ok =
               compile_ok?("pub def f(n Int53) Int53 := case n do\n  0 -> 0\n  1 -> 1\nend")
    end

    @tag :rust
    test "the non-exhaustive `case` panics on the uncovered arm (rustc)" do
      src =
        "type C := A(n Int53) | B(n Int53)\n" <>
          "def f(c C) Int53 := case c do\n  A(_) -> 7\nend\n" <>
          "def hit() Int53 := f(A(1))\ndef miss() Int53 := f(B(2))"

      rust = Rian.Lower.rust_program(Rian.Decl.parse(src))
      assert rust =~ ~s/_ => panic!("{}", "case: no clause matched")/

      case System.find_executable("rustc") do
        nil ->
          :ok

        rustc ->
          main = """

          fn main() {
              assert_eq!(hit(), 7);
              let r = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| miss()));
              assert!(r.is_err());
              println!("ok");
          }
          """

          dir =
            Path.join(System.tmp_dir!(), "rian_case_panic_#{System.unique_integer([:positive])}")

          rs = dir <> ".rs"
          bin = dir
          File.write!(rs, rust <> main)
          {out, code} = System.cmd(rustc, ["-A", "warnings", "--edition", "2021", rs, "-o", bin])
          assert code == 0, "rustc failed:\n#{out}"
          assert {"ok\n", 0} = System.cmd(bin, [])
      end
    end
  end
end

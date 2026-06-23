defmodule Rian.ReachHonestyPropertyTest do
  @moduledoc """
  Generative reach-honesty property (ADR-0087 §1, Stage 1).

  The reach matrix's honesty currently rests on a hand-picked corpus
  (`reach_rust_honesty_test`) — honesty *by selection bias*. This is the property
  form: a seeded `:rand` generator builds **well-typed-by-construction** integer
  programs over a random numeric width, and for every one asserts the ADR-0087
  invariant on the densest blocker surface (the ADR-0064 width contract):

    * **over-claim (the safety property):** if `Rian.Reach` claims `:rs`, the
      emitted Rust must compile under `rustc`. A rejection is a P0 honesty bug — the
      matrix lied. The Rust emitter raising is the same lie (it claimed reach it
      cannot deliver).
    * **width contract (both directions):** a fixed-width program reaches `:rs`
      (Rust has the integer type) and a bignum `Int` does not; `:js` is reached iff
      the width fits `2^53` (ADR-0064). These catch a reach *regression* a fixed
      corpus would not.

  Stage 2 (ADR-0087 §2-4) adds **type-directed generation** over compound `Option`/`Vec`
  return types and **capability-preserving shrinking**: a failing type is reduced to its
  minimal still-failing form before reporting (the shrinker is itself unit-tested against
  a synthetic predicate, in the default loop). It asserts the same two SAFE invariants —
  never replicating Reach's logic.

  `@tag :rust` — the property tests are excluded from the default `mix test` and run under
  `mix test.all` (the toolchain lane); the shrinker unit test needs no toolchain.
  Deterministic: the fixed `@seed` (and a deterministic per-type value) reproduce every
  program; a failure prints the minimal source and the seed.

  The compound property **runs** `f()` on the real toolchain per target — `:ex` on the
  BEAM, `:rs` as a compiled `rustc` *binary*, `:js` under `node` — serializes each result
  to one canonical form (Rust's `{:?}`), and asserts: every claimed target runs and
  produces a value (over-claim), and **every reached target's value is byte-equal**
  (cross-target equivalence — the full ADR-0087 §1 "compiles **and runs**", plus the
  portability guarantee). Generated programs are first passed through the type gate
  (`Rian.Check`) — a checker-rejected program is a generator artefact, not a reach lie, so
  it is excluded (ADR-0087 §3). (`:jvm` is reach-checked but not run here — no `kotlinc`.)
  """
  use ExUnit.Case, async: false

  alias Rian.{Beam, Check, Decl, JS, Lower, Reach}

  @seed {0x5EED, 0x0087, 0x64}
  @runs 40
  @depth 3

  # Stage 2 (type-directed compound types) — the generated return types nest
  # `Option`/`Vec` over the leaf set below; the value is a deterministic type-directed
  # term, the type is random.
  @runs2 40
  @depth2 3
  @leaves [:bool, :int53, :int64, :string]
  @all MapSet.new([:ex, :rs, :js, :jvm])

  # a JS serializer producing Rust's `{:?}` canonical form (`Some(x)`/`None`, `[a, b]`,
  # quoted strings) — so `f()`'s value compares byte-equal across BEAM/JS/Rust. A sum value
  # lowers to a tagged object `{ $: "Ctor", _0: … }` (ADR-0049 §3b, positional keys), a list to
  # a plain array — discriminated by the `$` tag, distinct from a `String` value.
  @js_show ~S"""
  function __show(x){
    if(x!==null&&typeof x==="object"&&x.$!==undefined){
      if(x.$==="Some")return "Some("+__show(x._0)+")";
      if(x.$==="None")return "None";
      return String(x.$);
    }
    if(Array.isArray(x))return "["+x.map(__show).join(", ")+"]";
    if(typeof x==="string")return JSON.stringify(x);
    return String(x);
  }
  """

  # Every fixed width is Rust-representable (two's-complement wrap, ADR-0064), so it
  # reaches `:rs`; the arbitrary-precision `Int` (BEAM bignum / JS BigInt) does not.
  @widths ~w(Int Int53 Int32 Int16 Int8 Int64 Int128)
  # `:js` is reached iff the width fits 2^53 (ADR-0064): `Int`, `Int53`, and
  # `Int32`-and-smaller; `Int64`/`Int128` are rejected on JS.
  @js_widths ~w(Int Int53 Int32 Int16 Int8)

  setup do
    :rand.seed(:exsss, @seed)
    :ok
  end

  @tag :rust
  test "generated integer programs: reach claims match rustc + the width contract" do
    case System.find_executable("rustc") do
      nil ->
        :ok

      rustc ->
        for _ <- 1..@runs do
          w = Enum.random(@widths)
          src = "def f(x #{w}, y #{w}) #{w} := #{gen_expr(@depth, ["x", "y"])}"
          reach = src |> Decl.parse() |> Reach.analyze() |> reach_of("f")

          # width contract — both directions (under-claim regression guard).
          assert :rs in reach == (w != "Int"),
                 "width #{w}: :rs reach is #{:rs in reach}, expected #{w != "Int"}\n#{src}\nseed=#{inspect(@seed)}"

          assert :js in reach == w in @js_widths,
                 "width #{w}: :js reach is #{:js in reach}, expected #{w in @js_widths}\n#{src}\nseed=#{inspect(@seed)}"

          # over-claim — the safety property: a :rs claim must compile under rustc.
          if :rs in reach, do: assert_rustc_ok(rustc, src, w)
        end
    end
  end

  # Stage 2 (ADR-0087 §2-4): type-directed generation over compound `Option`/`Vec`
  # return types + multi-target run + shrinking. SAFE invariants (no Reach logic is
  # replicated): each reach claim is checked against the real toolchain (:rs compiles
  # under rustc, :ex runs on the BEAM, :js runs under node), and the reach must EQUAL the
  # independent `expected_reach/1` spec oracle — exact membership BOTH directions (so an
  # under-claim is caught, not just an over-claim). The compound value is a `2^53 + 1`
  # `Int64` (it exceeds `Int53`, so it adopts the declared width through its constructor),
  # which makes the cross-target equality check stress precision — a `:js` claim that
  # emitted it as a 64-bit float would diverge from the BEAM/Rust value.
  @tag :rust
  test "type-directed compound programs: reach == expected_reach + cross-target value equality" do
    case System.find_executable("rustc") do
      nil ->
        :ok

      rustc ->
        for _ <- 1..@runs2 do
          t = gen_type(@depth2)

          if fail_reason(rustc, t) != nil do
            # shrink the failing type to its minimal still-failing form before reporting.
            min = minimize(t, fn x -> fail_reason(rustc, x) != nil end)

            flunk(
              "reach-honesty #{fail_reason(rustc, min)}: minimal failing type #{ty_str(min)}\n" <>
                "def f() #{ty_str(min)} := #{val_det(min)}\nseed=#{inspect(@seed)}"
            )
          end
        end
    end
  end

  test "the shrinker minimizes a failing type to its smallest still-failing form" do
    # a synthetic failure predicate (no toolchain): an `Int64` nested under at least one
    # constructor. Proves `minimize/2` converges to a minimal reproducer.
    fails? = fn t -> nested_int64?(t) end
    big = {:vec, {:option, {:vec, :int64}}}

    assert fails?.(big)
    assert minimize(big, fails?) in [{:option, :int64}, {:vec, :int64}]
    refute fails?.(:int64)
  end

  # a well-typed expression of the function's width over its params: a var, a small
  # literal (a bare int literal adopts the neighbouring declared width, ADR-0064 — and
  # stays under the Int8 ceiling), or a wrapping arithmetic combination of the same.
  defp gen_expr(0, vars), do: leaf(vars)

  defp gen_expr(depth, vars) do
    case :rand.uniform(5) do
      n when n <= 2 ->
        leaf(vars)

      _ ->
        op = Enum.random(["+", "-", "*"])
        "(#{gen_expr(depth - 1, vars)} #{op} #{gen_expr(depth - 1, vars)})"
    end
  end

  defp leaf(vars) do
    if :rand.uniform(2) == 1,
      do: Enum.random(vars),
      else: Integer.to_string(:rand.uniform(100) - 1)
  end

  defp reach_of(rep, name), do: Reach.entry(rep, name).reach

  defp assert_rustc_ok(rustc, src, w) do
    rust =
      try do
        Lower.rust_program(Decl.parse(src))
      rescue
        e ->
          flunk(
            "Reach claims :rs (width #{w}) but the Rust emitter raised: " <>
              "#{Exception.message(e)}\n#{src}\nseed=#{inspect(@seed)}"
          )
      end

    {ok?, out} = rustc_compiles?(rustc, rust)

    assert ok?,
           "Reach claims :rs (width #{w}) but rustc rejected the emitted Rust:\n" <>
             "#{src}\n--- rust ---\n#{rust}\n--- rustc ---\n#{out}\nseed=#{inspect(@seed)}"
  end

  # write `rust` to a temp lib crate and compile it — `{compiled?, output}`.
  defp rustc_compiles?(rustc, rust) do
    base = Path.join(System.tmp_dir!(), "rian_rhp_#{System.unique_integer([:positive])}")
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

      {code == 0, out}
    after
      File.rm(rs)
      File.rm(lib)
    end
  end

  # ── Stage 2: type-directed generation + shrinking ───────────────────────────

  # `nil` if return type `t` is reach-honest (or outside the well-typed domain — see
  # `valid?`), else the failing kind. SAFE: never replicates Reach's implementation. Each
  # reach claim is verified by *running* `f()` on the real toolchain (`:ex` BEAM, `:rs` rustc
  # binary, `:js` node) and serializing the result to one canonical form (Rust `{:?}`):
  #   * reach mismatch — the reach must EQUAL `expected_reach(t)` (an independent spec oracle),
  #     closing BOTH the over- and under-claim directions for every type (`:reach_mismatch`);
  #   * over-claim (run) — a claimed target must run + produce a value (`:run_failure`);
  #   * cross-target equality — every reached, runnable target must agree (`:divergence`).
  # The compound value uses a `2^53 + 1` `Int64` (see `val_det`), so the equality check
  # actually stresses precision — a `:js` claim that emitted it as a float would diverge.
  # (`:jvm` is reached-checked but not run here — no kotlinc in this lane.)
  defp fail_reason(rustc, t) do
    src = "def f() #{ty_str(t)} := #{val_det(t)}"

    # only well-typed programs are in scope (ADR-0087 §3) — the checker rejecting one
    # is a generator artefact (e.g. a nested-parametric list literal), not a reach lie.
    if not valid?(src) do
      nil
    else
      try do
        reach = src |> Decl.parse() |> Reach.analyze() |> reach_of("f")

        values =
          [{:ex, beam_value(src)}] ++
            if(:rs in reach, do: [{:rs, rust_value(rustc, src)}], else: []) ++
            if(:js in reach, do: [{:js, js_value(src)}], else: [])

        cond do
          # exact membership BOTH directions (closes the under-claim gap for compounds,
          # ADR-0087 §3): the reach must EQUAL the independently-derived spec reach, not
          # merely be a superset of the claimed-and-run targets.
          reach != expected_reach(t) -> :reach_mismatch
          Enum.any?(values, fn {_, v} -> v == :error end) -> :run_failure
          not consistent?(values) -> :divergence
          true -> nil
        end
      rescue
        _ -> :crash
      end
    end
  end

  # every value present (a `:skip` = toolchain absent, ignored) must be byte-equal.
  defp consistent?(values) do
    case for({_, v} <- values, v != :skip, do: v) do
      [] -> true
      [h | rest] -> Enum.all?(rest, &(&1 == h))
    end
  end

  # the program passes the type gate — the well-typedness precondition (ADR-0087 §3).
  defp valid?(src) do
    Check.check(src) == :ok
  rescue
    _ -> false
  end

  # `f()`'s value on each target as Rust's `{:?}` canonical string, or `:error` if the
  # claimed target fails to compile/run, or `:skip` if the toolchain is unavailable.
  defp beam_value(src) do
    {:ok, mod} = Beam.load(src, :"rian_rhp_beam_#{System.unique_integer([:positive])}")
    canon_beam(apply(mod, :f, []))
  rescue
    _ -> :error
  catch
    _, _ -> :error
  end

  defp canon_beam(true), do: "true"
  defp canon_beam(false), do: "false"
  defp canon_beam(:none), do: "None"
  defp canon_beam({:some, x}), do: "Some(#{canon_beam(x)})"
  defp canon_beam(x) when is_integer(x), do: Integer.to_string(x)
  defp canon_beam(x) when is_binary(x), do: "\"#{x}\""
  defp canon_beam(x) when is_list(x), do: "[#{Enum.map_join(x, ", ", &canon_beam/1)}]"

  defp rust_value(rustc, src) do
    rust = Lower.rust_program(Decl.parse(src)) <> "\nfn main() { println!(\"{:?}\", f()); }\n"
    base = Path.join(System.tmp_dir!(), "rian_rhp_#{System.unique_integer([:positive])}")
    rs = base <> ".rs"
    File.write!(rs, rust)

    try do
      with {_o, 0} <-
             System.cmd(rustc, ["-A", "warnings", "--edition", "2021", "-o", base, rs],
               stderr_to_stdout: true
             ),
           {out, 0} <- System.cmd(base, [], stderr_to_stdout: true) do
        String.trim(out)
      else
        _ -> :error
      end
    after
      File.rm(rs)
      File.rm(base)
    end
  rescue
    _ -> :error
  end

  defp js_value(src) do
    case System.find_executable("node") do
      nil ->
        :skip

      node ->
        path = Path.join(System.tmp_dir!(), "rian_rhp_#{System.unique_integer([:positive])}.mjs")
        File.write!(path, JS.compile(src) <> "\n" <> @js_show <> "console.log(__show(f()));\n")

        try do
          case System.cmd(node, [path], stderr_to_stdout: true) do
            {out, 0} -> String.trim(out)
            _ -> :error
          end
        after
          File.rm(path)
        end
    end
  rescue
    _ -> :error
  end

  # greedily shrink `t` to a minimal value still satisfying `fails?`.
  defp minimize(t, fails?) do
    case Enum.find(shrink_type(t), fails?) do
      nil -> t
      smaller -> minimize(smaller, fails?)
    end
  end

  # structurally-smaller types, each still a valid type (capability/shape-preserving):
  # unwrap a constructor, simplify a width, or shrink a child and re-wrap.
  defp shrink_type(:int64), do: [:int53]
  defp shrink_type({:option, t}), do: [t | Enum.map(shrink_type(t), &{:option, &1})]
  defp shrink_type({:vec, t}), do: [t | Enum.map(shrink_type(t), &{:vec, &1})]
  defp shrink_type(_atomic), do: []

  defp gen_type(0), do: Enum.random(@leaves)

  defp gen_type(depth) do
    case :rand.uniform(6) do
      n when n <= 4 -> Enum.random(@leaves)
      5 -> {:option, gen_type(depth - 1)}
      6 -> {:vec, gen_type(depth - 1)}
    end
  end

  defp ty_str(:bool), do: "Bool"
  defp ty_str(:int53), do: "Int53"
  defp ty_str(:int64), do: "Int64"
  defp ty_str(:string), do: "String"
  defp ty_str({:option, t}), do: "Option(#{ty_str(t)})"
  defp ty_str({:vec, t}), do: "Vec(#{ty_str(t)})"

  # a deterministic, type-directed value of `t` (so generation + shrinking reproduce):
  # `Some`/single-element `[_]` so a nested leaf actually manifests.
  defp val_det(:bool), do: "true"
  defp val_det(:int53), do: "1"
  # 2^53 + 1 — exceeds Int53, so the literal MUST adopt the declared `Int64` width (a small
  # literal stays Int53 and would not manifest the width). It is exact in BEAM bignum and
  # rustc `i64`, and would LOSE precision as a JS 64-bit float — so the cross-target value
  # check actually stresses the densest honesty surface (a `:js` claim that can't represent it).
  defp val_det(:int64), do: "9007199254740993"
  defp val_det(:string), do: "\"s\""
  defp val_det({:option, t}), do: "Some(#{val_det(t)})"
  defp val_det({:vec, t}), do: "[#{val_det(t)}]"

  # The reach a well-typed return of type `t` MUST have — derived independently of
  # `Rian.Reach` (the spec outcome, not its implementation; the same discipline as the
  # width test's `@js_widths` oracle). Every leaf/compound here reaches all four targets
  # EXCEPT a **bare** `Int64` return (> 2^53), which the JS boundary rejects
  # (`reject_wide_int!`, off `:js`). An `Int64` **nested** in an `Option`/`Vec` is faithfully
  # `:js`-reachable as a BigInt — verified empirically by running a `2^53 + 1` value
  # cross-target (BEAM bignum, rustc `i64`, and node BigInt all print it exactly). So only
  # the top-level bare-`Int64` leaf loses `:js`; everything else reaches all four.
  defp expected_reach(:int64), do: MapSet.new([:ex, :rs, :jvm])
  defp expected_reach(_t), do: @all

  # an `Int64` nested under at least one constructor (the shrinker's synthetic oracle).
  defp nested_int64?({:option, t}), do: has_int64?(t)
  defp nested_int64?({:vec, t}), do: has_int64?(t)
  defp nested_int64?(_), do: false

  defp has_int64?(:int64), do: true
  defp has_int64?({:option, t}), do: has_int64?(t)
  defp has_int64?({:vec, t}), do: has_int64?(t)
  defp has_int64?(_), do: false
end

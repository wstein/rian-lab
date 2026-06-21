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

  Remaining (Stage 2 cont.): the `:js`/`node` and BEAM emit-**and-run** directions (this
  checks `rustc` *compilation*).
  """
  use ExUnit.Case, async: false

  alias Rian.{Decl, Lower, Reach}

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
  # return types + shrinking. Two SAFE invariants (no Reach logic is replicated):
  #   * over-claim — a :rs claim must compile under rustc (an emitter raise is a lie);
  #   * under-claim — a *fully-portable* type (no `Int64`/bignum) must reach all four.
  # A bare `Int64` literal does not adopt its width through a constructor, so exact
  # membership for non-portable compounds is deliberately NOT asserted.
  @tag :rust
  test "type-directed compound programs: :rs claims compile + portable types reach all four" do
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

  # `nil` if return type `t` is reach-honest, else the failing kind. SAFE: asserts
  # over-claim (a :rs claim must compile) and the portable-base under-claim only;
  # never replicates Reach. A parse/reach crash on a valid program is itself a fail.
  defp fail_reason(rustc, t) do
    src = "def f() #{ty_str(t)} := #{val_det(t)}"

    try do
      reach = src |> Decl.parse() |> Reach.analyze() |> reach_of("f")

      cond do
        portable?(t) and not MapSet.subset?(@all, reach) -> :underclaim
        :rs in reach and not elem(rustc_ok?(rustc, src), 0) -> :overclaim
        true -> nil
      end
    rescue
      _ -> :crash
    end
  end

  # emit + compile, treating an emitter raise as a (rejected, message) pair.
  defp rustc_ok?(rustc, src) do
    rustc_compiles?(rustc, Lower.rust_program(Decl.parse(src)))
  rescue
    e -> {false, Exception.message(e)}
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
  defp val_det(:int64), do: "1"
  defp val_det(:string), do: "\"s\""
  defp val_det({:option, t}), do: "Some(#{val_det(t)})"
  defp val_det({:vec, t}), do: "[#{val_det(t)}]"

  # a type is fully portable iff it contains no `Int64` (bignum widths aside, the
  # leaf set here is otherwise all-target).
  defp portable?(:int64), do: false
  defp portable?({:option, t}), do: portable?(t)
  defp portable?({:vec, t}), do: portable?(t)
  defp portable?(_), do: true

  # an `Int64` nested under at least one constructor (the shrinker's synthetic oracle).
  defp nested_int64?({:option, t}), do: has_int64?(t)
  defp nested_int64?({:vec, t}), do: has_int64?(t)
  defp nested_int64?(_), do: false

  defp has_int64?(:int64), do: true
  defp has_int64?({:option, t}), do: has_int64?(t)
  defp has_int64?({:vec, t}), do: has_int64?(t)
  defp has_int64?(_), do: false
end

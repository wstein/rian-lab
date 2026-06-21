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

  `@tag :rust` — excluded from the default `mix test`; runs under `mix test.all`
  (the toolchain lane). Deterministic: the fixed `@seed` reproduces every program;
  a failure prints the offending source and the seed.

  Stage 2 (ADR-0087 §2-4) — a type-directed Core generator with shrinking, and the
  `:js`/`node` emit-and-run direction — is its own effort.
  """
  use ExUnit.Case, async: false

  alias Rian.{Decl, Lower, Reach}

  @seed {0x5EED, 0x0087, 0x64}
  @runs 40
  @depth 3

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

      assert code == 0,
             "Reach claims :rs (width #{w}) but rustc rejected the emitted Rust:\n" <>
               "#{src}\n--- rust ---\n#{rust}\n--- rustc ---\n#{out}\nseed=#{inspect(@seed)}"
    after
      File.rm(rs)
      File.rm(lib)
    end
  end
end

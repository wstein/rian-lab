defmodule Rian.ExternalReachHonestyTest do
  @moduledoc """
  Generative reach-honesty for `@external` (ADR-0068 / ADR-0086 §2).

  An external's host body is emitted **verbatim** — each target emitter trusts the
  string and only checks that it does not *raise* (`Rian.Tour.Examples.safe_emit`).
  So a body that is wrong for a **typed** target (rustc/kotlinc) sails through
  emission, and `Rian.Reach` still claims that target (it declares a body, ADR-0068
  §2). The portability matrix is then **dishonest** unless the toolchain actually
  accepts the body — a silent hole the emit-time checks cannot see.

  This is the CI tripwire that closes it: for every external claiming a typed target,
  the lowered program must really compile on that target's toolchain. The `sentinel`
  case proves the gap is real — a malformed `:rs` body is *claimed* by Reach and
  *emitted* without raising, yet `rustc` rejects it; only this test catches it.

  The toolchain cases are `@tag`ged (`:rust`/`:jvm`) so they run under `mix test.all`,
  and no-op when the toolchain is absent (CI parity, ADR-0026).
  """
  use ExUnit.Case, async: false

  alias Rian.{Decl, JVM, Lower, Reach}

  # externals with VALID typed-target host bodies — the positive corpus. The `Unit`
  # cases gate the void-external return mapping (ADR-0068): `Unit` → Rust `()` /
  # Kotlin `Unit`, so a console-style void external type-checks on the typed targets
  # (it claimed `Symbol` before, which Rust/JVM console calls do not return).
  @rs_ok [
    {"mag", ~S|@external(:rs, "x.abs()") pub def mag(x val Int64) Int64|},
    {"inc", ~S|@external(:rs, "x + 1") pub def inc(x val Int64) Int64|},
    {"out", ~S|@external(:rs, "println!(\"{}\", s)") pub def out(s String) Unit|}
  ]

  @jvm_ok [
    {"mag", ~S|@external(:jvm, "Math.abs(x)") pub def mag(x val Int64) Int64|},
    {"out", ~S|@external(:jvm, "println(s)") pub def out(s String) Unit|}
  ]

  # a host body that is wrong for Rust (no such method) — claimed by Reach, emitted
  # verbatim, and rejected only by rustc. The sentinel that the tripwire must catch.
  @rs_bad ~S|@external(:rs, "x.no_such_method_zzz()") pub def bad(x val Int64) Int64|

  describe "Reach claims exactly the declared-body targets (ADR-0068 §2)" do
    test "a valid typed-target external is reported reaching that target" do
      for {name, src} <- @rs_ok do
        rep = src |> Decl.parse() |> Reach.analyze()
        assert :rs in Reach.entry(rep, name).reach
      end
    end

    test "the malformed `:rs` external is STILL claimed `:rs` — the verbatim-trust gap" do
      rep = @rs_bad |> Decl.parse() |> Reach.analyze()

      assert :rs in Reach.entry(rep, "bad").reach,
             "Reach trusts a declared host body; only the toolchain can refute it"
    end

    test "the emitter does NOT raise on the malformed body (it emits verbatim)" do
      # the heart of the gap: emission succeeds, so an emit-time check (`safe_emit`)
      # can never catch a host body that is bad for a typed target.
      assert Lower.rust_program(Decl.parse(@rs_bad)) =~ "no_such_method_zzz"
    end

    test "a `Unit` (void) external lowers to Rust `()` and Kotlin `Unit`, not a passthrough" do
      rs = ~S|@external(:rs, "println!(\"{}\", s)") pub def out(s String) Unit|
      assert Lower.rust_program(Decl.parse(rs)) =~ "fn out(s: &str) -> ()"

      jvm = ~S|@external(:jvm, "println(s)") pub def out(s String) Unit|
      assert JVM.compile(jvm) =~ "fun out(a0: String): Unit"
    end
  end

  describe "every typed-target external actually compiles (the tripwire)" do
    @tag :rust
    test "valid `:rs` externals compile under rustc" do
      for {name, src} <- @rs_ok do
        assert rustc_ok?(Lower.rust_program(Decl.parse(src))) in [:ok, :no_rustc],
               "#{name}: a `:rs` external claimed reach but rustc rejected its host body"
      end
    end

    @tag :rust
    test "SENTINEL — a malformed `:rs` external is caught by rustc (the gap is real, now gated)" do
      case rustc_ok?(Lower.rust_program(Decl.parse(@rs_bad))) do
        :no_rustc ->
          :ok

        result ->
          assert match?({:error, _}, result),
                 "the tripwire must reject a malformed host body that emission + reach accept"
      end
    end

    @tag :jvm
    test "valid `:jvm` externals compile under kotlinc" do
      for {name, src} <- @jvm_ok do
        assert kotlinc_ok?(JVM.compile(src)) in [:ok, :no_kotlinc],
               "#{name}: a `:jvm` external claimed reach but kotlinc rejected its host body"
      end
    end
  end

  # ── toolchain helpers (no-op when the toolchain is absent — CI parity) ────────
  defp rustc_ok?(rust) do
    case System.find_executable("rustc") do
      nil ->
        :no_rustc

      rustc ->
        src = Path.join(System.tmp_dir!(), "rian_ext_#{System.unique_integer([:positive])}.rs")
        out = src <> ".meta"
        File.write!(src, rust)

        try do
          {o, code} =
            System.cmd(
              rustc,
              [
                "--crate-type",
                "lib",
                "--edition",
                "2021",
                "-A",
                "warnings",
                "--emit=metadata",
                src,
                "-o",
                out
              ],
              stderr_to_stdout: true
            )

          if code == 0, do: :ok, else: {:error, o}
        after
          File.rm(src)
          File.rm(out)
        end
    end
  end

  defp kotlinc_ok?(kt) do
    case System.find_executable("kotlinc") do
      nil ->
        :no_kotlinc

      kotlinc ->
        dir = Path.join(System.tmp_dir!(), "rian_ext_kt_#{System.unique_integer([:positive])}")
        File.mkdir_p!(dir)
        src = Path.join(dir, "Main.kt")
        File.write!(src, kt)

        try do
          {o, code} = System.cmd(kotlinc, [src, "-d", dir], stderr_to_stdout: true)
          if code == 0, do: :ok, else: {:error, o}
        after
          File.rm_rf(dir)
        end
    end
  end
end

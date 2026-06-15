defmodule Rian.ComposeDriverWholeFixpointTest do
  # async: false — loads the verified ports + the driver, then `build/2` compiles
  # the driver's OWN whole source into a second driver loaded at runtime.
  use ExUnit.Case, async: false

  alias Rian.Beam

  # THE BUILD COMPILES THE BUILD (ADR-0063 Step 3 / §4 — the v1==v2 capstone). The
  # three stage loops (`compose_lexer`/`compose_decl_whole`/`compose_beam_whole`) each
  # close on one stage's source. This one closes on the DRIVER itself: the reference
  # driver v1 (selfhost_compose_real_sum.rian, compiled by Rian.Beam) compiles its
  # OWN whole source — lexer + decl-parser + beam-backend composition, cross-module
  # remote calls, tuple/atom abstract-form construction, and the `@external` FFI
  # functions whose host expressions (`:erlang.binary_to_list(s)`, `:compile.forms`,
  # `:code.load_binary`) are parsed and spliced as bodies — into a v2 driver.
  #
  # v2 is then exercised exactly as v1: it `build`s real programs into loadable,
  # runnable modules, and v1 and v2 agree on every result. That is v1==v2 on the
  # driver — the composition pipeline reproducing itself.
  #
  # Honesty (mirrors Rian.SelfHost @composition): the loop is self-COMPILING, not
  # self-CHECKING — Rian.Check/Exhaustiveness/Capability are not in `build`.

  @driver_file "examples/rian/selfhost_compose_real_sum.rian"
  @driver_src File.read!(@driver_file)

  setup_all do
    {:ok, _} =
      Beam.load(File.read!("examples/rian/selfhost_lexer_v2.rian"), :"Elixir.SelfhostLexerV2")

    {:ok, _} = Beam.load(File.read!("examples/rian/selfhost_decl.rian"), :"Elixir.SelfhostDecl")
    {:ok, _} = Beam.load(File.read!("examples/rian/selfhost_beam.rian"), :"Elixir.SelfhostBeam")

    {:ok, _} =
      Beam.load(File.read!("examples/rian/selfhost_exhaust.rian"), :"Elixir.SelfhostExhaust")

    {:ok, _} = Beam.load(File.read!("examples/rian/selfhost_cap.rian"), :"Elixir.SelfhostCap")

    {:ok, v1} = Beam.load(@driver_src, :rian_driver_v1)

    # v1 compiles its OWN whole source into v2 — the build compiling the build.
    forms = v1.compile_module(@driver_src, :"RianDriverV2_#{System.unique_integer([:positive])}")
    {:ok, m, bin} = :compile.forms(forms, [:return_errors])
    {:module, ^m} = :code.load_binary(m, ~c"nofile", bin)

    {:ok, v1: v1, v2: m}
  end

  # programs the driver compiles; for each, v1.build and v2.build must produce
  # modules whose listed calls return identical results. Covers nullary + applied
  # sum variants, arithmetic, `if`, and multi-clause pattern dispatch — the surface
  # the driver lowers.
  @corpus [
    {"type Box := B(Int53)\ndef wrap(n Int53) Box := B(n)\ndef unwrap(b Box) Int53\ndef unwrap(B(n)) := n",
     [{:wrap, [9]}, {:unwrap, [{:b, 42}]}]},
    {"def add(a Int53, b Int53) Int53 := a + b\ndef poly(a Int53, b Int53, c Int53) Int53 := a * b + c",
     [{:add, [3, 4]}, {:poly, [2, 5, 1]}]},
    {"def max(a Int53, b Int53) Int53 := if a > b do a else b end",
     [{:max, [3, 7]}, {:max, [9, 2]}]},
    {"type Shape := Circle(Int53) | Rect(Int53, Int53)\ndef area(s Shape) Int53\ndef area(Circle(r)) := r * r\ndef area(Rect(w, h)) := w * h",
     [{:area, [{:circle, 5}]}, {:area, [{:rect, 3, 4}]}]}
  ]

  describe "the build compiles the build — v1 and v2 drivers agree (v1==v2)" do
    test "v2 (the self-built driver) builds + runs programs identically to v1", %{v1: v1, v2: v2} do
      for {prog, calls} <- @corpus do
        m1 = v1.build(prog, :"DrvProgV1_#{System.unique_integer([:positive])}")
        m2 = v2.build(prog, :"DrvProgV2_#{System.unique_integer([:positive])}")

        for {fname, args} <- calls do
          r1 = apply(m1, fname, args)
          r2 = apply(m2, fname, args)

          assert r1 == r2,
                 "v1/v2 driver disagree on #{prog} :: #{fname}(#{inspect(args)}) — #{inspect(r1)} vs #{inspect(r2)}"
        end
      end
    end

    test "v2 is the WHOLE driver — it exports the real entry points", %{v2: v2} do
      assert @driver_src =~ "mod"
      assert @driver_src =~ "pub def build(src String, modname Symbol) Symbol"
      assert function_exported?(v2, :build, 2)
      assert function_exported?(v2, :compile_module, 2)
    end
  end
end

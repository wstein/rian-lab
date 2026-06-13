defmodule Rian.TargetsTest do
  # async: false — compiles modules through the global compiler/code server.
  use ExUnit.Case, async: false

  alias Rian.{Beam, Decl, Reach}

  describe "@targets(…) parsing (ADR-0058 §2)" do
    test "the contract is parsed onto the module" do
      [mod] =
        Decl.parse("""
        @targets(ex, rs, js)
        mod M do
          pub def f(n Int64) Int64 := n
        end
        """).mods

      assert mod.targets == [:ex, :rs, :js]
    end

    test "a module with no annotation has no contract" do
      [mod] = Decl.parse("mod M do\n  pub def f(n Int64) Int64 := n\nend\n").mods
      assert mod.targets == nil
    end

    test "an unknown target is rejected" do
      assert_raise Decl.Error, ~r/unknown target `wasm`/, fn ->
        Decl.parse("@targets(ex, wasm)\nmod M do\n  pub def f(n Int64) Int64 := n\nend\n")
      end
    end

    test "@targets may only precede a mod" do
      assert_raise Decl.Error, ~r/may only precede a `mod`/, fn ->
        Decl.parse("@targets(ex)\ndef f(n Int64) Int64 := n\n")
      end
    end
  end

  describe "the @targets contract gate (Rian.Reach.gate!)" do
    test "a portable module satisfies @targets(ex, rs, js)" do
      src = """
      @targets(ex, rs, js)
      mod Geo do
        pub def square(n Int64) Int64 := n * n
      end
      """

      assert Reach.check_contracts(Decl.parse(src)) == :ok
      assert [_] = Beam.compile_program(src)
    end

    test "a pub function using host FFI fails an @targets(ex, rs, js) contract" do
      src = """
      @targets(ex, rs, js)
      mod Sys do
        pub def now() Int64 := :erlang.system_time()
      end
      """

      assert {:error, msg} = Reach.check_contracts(Decl.parse(src))
      assert msg =~ "Sys.now cannot reach [:js, :rs]"

      assert_raise Reach.Error, ~r/contract not met/, fn -> Beam.compile_program(src) end
    end

    test "an @targets(ex) contract permits host FFI (BEAM-only promise)" do
      src = """
      @targets(ex)
      mod Sys do
        pub def now() Int64 := :erlang.system_time()
      end
      """

      assert Reach.check_contracts(Decl.parse(src)) == :ok
      assert [_] = Beam.compile_program(src)
    end

    test "only pub functions are gated; a private FFI helper is not (unless reached)" do
      src = """
      @targets(ex, rs, js)
      mod M do
        pub def go(n Int64) Int64 := n
        def helper() Int64 := :erlang.system_time()
      end
      """

      assert Reach.check_contracts(Decl.parse(src)) == :ok
    end

    test "a pub function inherits a called helper's FFI pin and fails the contract" do
      src = """
      @targets(ex, rs, js)
      mod M do
        pub def go() Int64 := helper()
        def helper() Int64 := :erlang.system_time()
      end
      """

      assert {:error, msg} = Reach.check_contracts(Decl.parse(src))
      assert msg =~ "M.go cannot reach"
    end

    test "a module with no contract is never gated, even with FFI" do
      src = "mod M do\n  pub def now() Int64 := :erlang.system_time()\nend\n"
      assert Reach.check_contracts(Decl.parse(src)) == :ok
    end
  end
end

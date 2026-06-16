defmodule Rian.GradualTest do
  # async: false — Beam.compile loads modules into the VM.
  use ExUnit.Case, async: false

  @moduledoc """
  `__Unknown` — the sound gradual "open" type (ADR-0076). The invariant under test
  is the **gradual guarantee**: any value flows *into* `__Unknown`, but a `__Unknown`
  value cannot stand where a concrete type is required without being NARROWED first —
  so it can never leak unchecked into typed code (fully-typed Rian stays sound).
  """

  defp check(src) do
    Rian.Decl.compile(src)
    :ok
  rescue
    e -> {:error, Exception.message(e)}
  end

  describe "assignment INTO __Unknown (it is the top for assignment)" do
    test "a concrete value is assignable to a __Unknown return" do
      assert :ok = check("mod M do\n  pub def box(x Int53) __Unknown := x\nend")
    end

    test "__Unknown is assignable to __Unknown (identity passthrough)" do
      assert :ok = check("mod M do\n  pub def id(x __Unknown) __Unknown := x\nend")
    end

    test "any concrete type flows into __Unknown" do
      assert :ok =
               check(
                 "mod M do\n  pub def s(x String) __Unknown := x\n  pub def b(x Bool) __Unknown := x\nend"
               )
    end
  end

  describe "soundness — a __Unknown cannot be used AS a concrete type unnarrowed" do
    test "returning a __Unknown where Int53 is declared is rejected" do
      assert {:error, msg} = check("mod M do\n  pub def u(x __Unknown) Int53 := x\nend")
      assert msg =~ "__Unknown"
    end

    test "the rejection message names the declared concrete type" do
      assert {:error, msg} = check("mod M do\n  pub def u(x __Unknown) String := x\nend")
      assert msg =~ "String"
    end
  end

  describe "narrowing recovers a concrete type (the runtime-checked consumption)" do
    test "a `case` over __Unknown with a wildcard type-checks and the field is concrete" do
      src = """
      mod M do
        type T := A(v Int53) | B
        pub def u(x __Unknown) Int53 :=
          case x do
            A(v) -> v
            _ -> 0
          end
      end
      """

      assert :ok = check(src)
    end

    test "narrowing WITHOUT a wildcard is rejected (must handle the non-matching value)" do
      # exhaustiveness forces the `_` — that IS the runtime check the human must write.
      src = """
      mod M do
        type T := A(v Int53) | B
        pub def u(x __Unknown) Int53 :=
          case x do
            A(v) -> v
          end
      end
      """

      assert {:error, msg} = check(src)
      assert msg =~ "exhaustive" or msg =~ "not covered"
    end
  end

  describe "__Unknown lowers to BEAM (erased to any())" do
    test "a __Unknown function compiles to real bytecode and runs" do
      {:ok, mod} =
        Rian.Beam.load(
          "mod GradMod do\n  pub def id(x __Unknown) __Unknown := x\nend",
          :"Elixir.GradMod"
        )

      assert mod.id(42) == 42
      assert mod.id("hi") == "hi"
    end
  end

  describe "the gradual guarantee — fully-typed code is untouched" do
    test "a module with ZERO __Unknown still type-checks exactly as before" do
      assert :ok = check("mod M do\n  pub def add(a Int53, b Int53) Int53 := a + b\nend")
      assert {:error, _} = check("mod M do\n  pub def bad(a Int53) String := a\nend")
    end
  end
end

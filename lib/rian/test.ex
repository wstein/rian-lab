defmodule Rian.Test do
  @moduledoc """
  Rian-native test framework (ADR-0057: "Rian source is sequential logic + tests").

  A test is a `@test def` — a zero-arity function returning `Bool` (`true` =
  pass). It compiles through the ordinary pipeline like any other function:

      @test def one_plus_one() Bool := 1 + 1 == 2

  This module is the **BEAM/ExUnit** lowering: it compiles a `.rian` test file to
  real bytecode and runs each `@test` function. `exunit/1` bridges them into the
  host's xUnit framework so each Rian test surfaces as its own ExUnit case (with
  host-formatted failures — until the `Show` protocol is wired for Rian-level
  diagnostics, ADR-0042). The same `@test` surface lowers to `#[test]` (Rust) and
  Vitest `it(…)` (JS) — those backends are deferred (BEAM-first).

  ## Use as an ExUnit bridge

      defmodule MyRianTest do
        use ExUnit.Case
        require Rian.Test
        Rian.Test.exunit("examples/rian/14_test_framework.rian")
      end

  ## Use programmatically

      Rian.Test.run(File.read!("examples/rian/14_test_framework.rian"))
      #=> [{"one_plus_one", :pass}, {"bad", {:fail, false}}]
  """
  alias Rian.{Beam, Decl}

  @doc "The names of the `@test def`s declared in `src`, in source order."
  def tests(src), do: Decl.parse(src).funcs |> Enum.filter(& &1.test?) |> Enum.map(& &1.name)

  @doc "Compile `src` to bytecode under `mod` and load it (idempotent reload)."
  def compile!(src, mod) do
    {:ok, ^mod} = Beam.load(src, mod)
    mod
  end

  @doc "Invoke one compiled test by name; returns its `Bool` result."
  def run_one(mod, name), do: apply(mod, String.to_atom(name), [])

  @doc """
  Compile `src` and run every `@test`, returning `[{name, :pass | {:fail, value}}]`.
  A test passes iff it returns `true`.
  """
  def run(src, mod \\ nil) do
    mod = mod || default_mod(src)
    compile!(src, mod)

    for n <- tests(src) do
      case run_one(mod, n) do
        true -> {n, :pass}
        other -> {n, {:fail, other}}
      end
    end
  end

  @doc "A stable module atom derived from the source (for one-off runs)."
  def default_mod(src), do: :"rian_test_#{:erlang.phash2(src)}"

  @doc """
  Define one ExUnit `test` per `@test` in the `.rian` file at `path` (read at
  compile time). Expand inside a `use ExUnit.Case` module.
  """
  defmacro exunit(path) do
    src = File.read!(path)
    names = tests(src)
    mod = :"rian_test_#{:erlang.phash2(path)}"

    cases =
      for n <- names do
        quote do
          test unquote("rian: " <> n) do
            assert Rian.Test.run_one(unquote(mod), unquote(n)) == true,
                   unquote("Rian @test `#{n}` did not return true")
          end
        end
      end

    quote do
      setup_all do
        Rian.Test.compile!(unquote(src), unquote(mod))
        :ok
      end

      unquote(cases)
    end
  end
end

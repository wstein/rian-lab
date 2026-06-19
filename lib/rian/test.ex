defmodule Rian.Test do
  use Rian.Ann

  @moduledoc """
  Rian-native test framework (ADR-0057: "Rian source is sequential logic + tests").

  A test is a `@test def` — a zero-arity function returning `Bool` (`true` =
  pass). It compiles through the ordinary pipeline like any other function:

      @test def one_plus_one() Bool := 1 + 1 == 2

  ## Assertion macros (ADR-0060 · ADR-0030)

  Every test source is compiled with `examples/rian/prelude_test.rian` prepended,
  so the ExUnit-style assertion vocabulary — `assert`/`refute`/`assert_eq`/
  `assert_neq`, hygienic Rian macros that expand to a plain `Bool` — is available
  to every `@test def` with no boilerplate (Rian macros are scope-local with no
  cross-file import, so injection is how the lib is shared):

      @test def doubles() Bool := assert_eq(double(21), 42)
      @test def positive() Bool := refute(sign(3) == -1)

  The macros emit no IR and need only built-in `==`/`!=`/`not`, so they lower
  cleanly on all three targets and add no prelude dependency.

  For richer **diagnostics**, the matcher family — `expect_eq`/`expect_neq`/
  `expect_true`/`expect_false` — returns `Outcome := Pass | Fail(String)` (ADR-0060
  §2: assertions are values, not exceptions) and names the mismatch on failure,
  formatted via string interpolation (ADR-0069):

      @test def doubles() Outcome := expect_eq(double(21), 42)
      #=> Fail("expected 42, got 41") when double misbehaves

  A `@test def` may return `Bool` or `Outcome`; `run`/`exunit` interpret both (a
  matcher's `Fail` message flows through), and the Rust/JS harnesses wrap an
  `Outcome` test to assert `Pass` and surface its message. The matchers are spelled
  `expect_*`, not the bare `eq`/`be` the ADR sketched, because the lib is prepended
  to every test source and a macro shadows a same-named function (a bare `eq` would
  hijack the `Eq` stdlib). `contain` (membership) stays deferred — it needs the
  `List` prelude linked, like `assert_in`.

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

  ## Per-target harness (ADR-0060 §3)

  `rust/1` and `js/1` lower the *same* `@test def`s to each target's idiomatic
  xUnit — Rust `#[test]` (run by `rustc --test`) and `node:test` (`node --test`).
  A `@test` is an ordinary `Bool` function, so it lowers like any other code; the
  harness only adds the per-target test wrapper that asserts it returns `true`.
  """
  alias Rian.{Beam, Decl}

  # The Rian-native assertion-macro lib (`assert`/`refute`/`assert_eq`/`assert_neq`,
  # ADR-0060/ADR-0030). Rian macros are scope-local with no cross-file import, so we
  # PREPEND this lib to every test source we compile — the macros then expand AST→AST
  # in `Decl.parse`/`Beam.load` and emit no IR, so every `@test def` gets the
  # ExUnit-style vocabulary for free, on all three targets. `@external_resource`
  # recompiles this module when the lib changes.
  @assert_prelude File.read!("examples/rian/prelude_test.rian")
  @external_resource "examples/rian/prelude_test.rian"

  @doc "The canonical assertion-macro lib prepended to every test source."
  @rian_sig "pub def assert_prelude() String"
  @spec assert_prelude() :: String.t()
  def assert_prelude, do: @assert_prelude

  # Make the assertion macros available to `src`'s `@test def`s.
  defp with_assertions(src), do: @assert_prelude <> "\n" <> src

  @doc "The names of the `@test def`s declared in `src`, in source order."
  @rian_sig "pub def tests(src String) Vec(String)"
  @spec tests(String.t()) :: [String.t()]
  def tests(src), do: Decl.parse(src).funcs |> Enum.filter(& &1.test?) |> Enum.map(& &1.name)

  # `@test def`s as `{name, return-type}`, so a per-target harness can branch on the
  # `Bool` vs `Outcome` (matcher) surface when emitting its assertion wrapper.
  defp test_specs(src),
    do: Decl.parse(src).funcs |> Enum.filter(& &1.test?) |> Enum.map(&{&1.name, &1.ret})

  @doc "Compile `src` to bytecode under `mod` and load it (idempotent reload)."
  @rian_sig "pub def compile!(src String, mod Symbol) Symbol"
  @spec compile!(String.t(), module()) :: module()
  def compile!(src, mod) do
    {:ok, ^mod} = Beam.load(with_assertions(src), mod)
    mod
  end

  @doc "Invoke one compiled test by name; returns its raw `Bool` or `Outcome` result."
  @rian_sig "pub def run_one(mod Symbol, name String) Bool"
  @spec run_one(module(), String.t()) :: term()
  def run_one(mod, name), do: apply(mod, String.to_atom(name), [])

  @doc """
  Interpret a test's raw return value as `:pass | {:fail, reason}`.

  A `@test def` may return either a `Bool` (`true` = pass — the original surface)
  or an `Outcome := Pass | Fail(String)` from a matcher (ADR-0060). Rian lowers the
  variants to `:pass` and `{:fail, msg}` on the BEAM, so a matcher's failure message
  flows straight through; a bare `false` becomes `{:fail, false}`.
  """
  @rian_sig "pub def outcome(raw _Unk) Outcome"
  @spec outcome(term()) :: :pass | {:fail, term()}
  def outcome(true), do: :pass
  def outcome(:pass), do: :pass
  def outcome({:fail, reason}), do: {:fail, reason}
  def outcome(other), do: {:fail, other}

  @doc """
  Compile `src` and run every `@test`, returning `[{name, :pass | {:fail, value}}]`.
  A test passes iff it returns `true` (Bool surface) or `Pass` (matcher `Outcome`);
  a matcher's `Fail(msg)` surfaces as `{:fail, msg}`.
  """
  @rian_sig "pub def run(src String) Vec((String, Outcome))"
  @rian_sig "pub def run(src String, mod Symbol) Vec((String, Outcome))"
  @spec run(String.t(), module() | nil) :: [{String.t(), :pass | {:fail, term()}}]
  def run(src, mod \\ nil) do
    mod =
      case mod do
        nil -> default_mod(src)
        m -> m
      end

    compile!(src, mod)

    for n <- tests(src), do: {n, outcome(run_one(mod, n))}
  end

  @doc "A stable module atom derived from the source (for one-off runs)."
  @rian_sig "pub def default_mod(src String) Symbol"
  @spec default_mod(String.t()) :: module()
  def default_mod(src), do: :"rian_test_#{:erlang.phash2(src)}"

  @doc """
  Lower `src` to a **Rust** test module (ADR-0060 §3): the functions plus a
  `#[test]` wrapper per `@test`. A `Bool` test asserts it returns `true`; an
  `Outcome` (matcher) test panics with the `Fail(msg)` so `rustc --test` reports
  *why* it failed. Compile/run with `rustc --test`.
  """
  @rian_sig "pub def rust(src String) String"
  @spec rust(String.t()) :: String.t()
  def rust(src) do
    # Use the **whole-program** Rust assembly (`rust_program`), not the per-function
    # `Decl.compile` path: it threads the cross-function signature table the call-site
    # borrow pass needs (ADR-0061), so generic functions that call one another
    # (`sort`→`insert`) lower with correct `&`/`.clone()` ownership coercion.
    fns = Rian.Lower.rust_program(Decl.parse(with_assertions(src)))

    wrappers =
      Enum.map_join(test_specs(src), "\n", fn {n, ret} ->
        check =
          if ret == "Outcome",
            do: "match #{n}() { Outcome::Pass => {}, Outcome::Fail(m) => panic!(\"{}\", m) }",
            else: "assert!(#{n}());"

        "#[test]\nfn rian_test_#{n}() { #{check} }"
      end)

    [fns, wrappers] |> Enum.reject(&(&1 == "")) |> Enum.join("\n\n")
  end

  @doc """
  Lower `src` to a **JS** test module (ADR-0060 §3): the functions plus a
  `node:test` case per `@test`. A `Bool` test asserts it returns `true`; an
  `Outcome` (matcher) test asserts `Pass`, surfacing the `Fail` message. Run with
  `node --test`.
  """
  @rian_sig "pub def js(src String) String"
  @spec js(String.t()) :: String.t()
  def js(src) do
    header = ~s|import { test } from "node:test";\nimport assert from "node:assert";\n|

    wrappers =
      Enum.map_join(test_specs(src), "\n", fn {n, ret} ->
        if ret == "Outcome" do
          ~s|test(#{inspect(n)}, () => { const o = #{n}(); assert.ok(o[0] === "Pass", o[1]); });|
        else
          ~s|test(#{inspect(n)}, () => assert.strictEqual(#{n}(), true));|
        end
      end)

    header <> "\n" <> Rian.JS.compile(with_assertions(src)) <> "\n\n" <> wrappers
  end

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
            case Rian.Test.outcome(Rian.Test.run_one(unquote(mod), unquote(n))) do
              :pass -> :ok
              {:fail, reason} -> flunk(unquote("Rian @test `#{n}` failed: ") <> inspect(reason))
            end
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

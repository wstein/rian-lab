defmodule Rian.ComposeFixpointTest do
  # async: false — loads real modules into the VM via :code.load_binary.
  use ExUnit.Case, async: false

  alias Rian.Beam

  # COMPOSITION fixpoint (ADR-0063 Step 3): the FIRST genuine composition rung.
  # `compose.rian` wires lex → parse → lower → forms DIRECTLY in Rian over
  # shared types — `compile(s) = forms(lower(parse(lex(s))))` — with no Elixir glue
  # between the stages. Its output IS Erlang abstract forms, so this test feeds them
  # to `:compile.forms`, loads the module, RUNS it, and asserts it behaves
  # IDENTICALLY to the full Elixir toolchain (`Rian.Beam` compiling the same source).
  #
  # This is the difference between per-stage equivalence (every other fixpoint) and
  # composition: here stage N consumes stage N-1's Rian output with no projection.

  setup_all do
    {:ok, mod} = Beam.load(File.read!("compiler/compose.rian"), :rian_compose)
    {:ok, mod: mod}
  end

  # build, compile, and load a 0/N-ary `f` whose body is the composed Rian form.
  defp compose_module(mod, expr, vars, modname) do
    form = mod.compile(expr)
    params = Enum.map(vars, fn v -> {:var, 0, var_atom(v)} end)
    arity = length(vars)

    forms = [
      {:attribute, 0, :module, modname},
      {:attribute, 0, :export, [{:f, arity}]},
      {:function, 0, :f, arity, [{:clause, 0, params, [], [form]}]}
    ]

    {:ok, ^modname, bin} = :compile.forms(forms, [:return_errors])
    {:module, ^modname} = :code.load_binary(modname, ~c"nofile", bin)
    modname
  end

  # match the pipeline's `cap`: upcase the first char only (`foo` -> `Foo`).
  defp var_atom(v) do
    <<c, rest::binary>> = Atom.to_string(v)
    String.to_atom(String.upcase(<<c>>) <> rest)
  end

  # the Elixir toolchain compiling the SAME expression as a function body.
  defp ref_module(expr, vars) do
    sig = Enum.map_join(vars, ", ", fn v -> "#{v} Int53" end)
    sig = if sig == "", do: "", else: sig
    src = "def f(#{sig}) Int53 := #{expr}"
    {:ok, m} = Beam.load(src, :"cmp_ref_#{System.unique_integer([:positive])}")
    m
  end

  # {expr, [free vars], [arg lists to run on both modules]}
  @corpus [
    {"a + b", [:a, :b], [[2, 3], [10, -4]]},
    {"a + b * c", [:a, :b, :c], [[1, 2, 3], [5, 6, 7]]},
    {"a * b + c", [:a, :b, :c], [[2, 3, 4]]},
    {"(a + b) * c", [:a, :b, :c], [[1, 2, 3], [4, 5, 6]]},
    {"a - b - c", [:a, :b, :c], [[10, 3, 2]]},
    {"a * (b + c)", [:a, :b, :c], [[2, 3, 4]]},
    {"x + y * z - w", [:x, :y, :z, :w], [[1, 2, 3, 4]]},
    {"2 + 3 * 4", [], [[]]},
    {"foo * bar + 1", [:foo, :bar], [[6, 7]]}
  ]

  describe "composition fixpoint — lex→parse→lower→forms (Rian) runs identically to Elixir" do
    test "the composed Rian pipeline compiles + runs a function equal to Rian.Beam's", %{mod: mod} do
      for {expr, vars, inputs} <- @corpus do
        composed =
          compose_module(mod, expr, vars, :"cmp_composed_#{System.unique_integer([:positive])}")

        ref = ref_module(expr, vars)

        for args <- inputs do
          assert apply(composed, :f, args) == apply(ref, :f, args),
                 "composed pipeline diverged from Elixir toolchain on `#{expr}` with #{inspect(args)}"
        end
      end
    end
  end

  describe "teeth — the stages genuinely COMPOSE (no inter-stage glue)" do
    test "lex feeds parse feeds lower feeds forms, end to end", %{mod: mod} do
      # the composed output is a real Erlang abstract form, built only by Rian.
      assert mod.compile("a + b * 2") ==
               {:op, 1, :+, {:var, 1, :A}, {:op, 1, :*, {:var, 1, :B}, {:integer, 1, 2}}}

      # and each intermediate is the next stage's input (shared types, no projection)
      assert mod.lex("a*2") == [{:t_id, "a"}, {:t_op, "*"}, {:t_num, "2"}]
      assert mod.lower(mod.parse(mod.lex("a*2"))) == {:c_bin, "*", {:c_id, "a"}, {:c_num, "2"}}
    end

    test "precedence survives the whole pipeline (a + b * c nests * under +)", %{mod: mod} do
      m = compose_module(mod, "a + b * c", [:a, :b, :c], :cmp_prec)
      # 2 + 3*4 = 14, not (2+3)*4 = 20 — precedence is preserved through composition
      assert m.f(2, 3, 4) == 14
    end
  end
end

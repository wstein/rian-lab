defmodule Rian.EquivLockTest do
  # async: false — Code.compile_string loads modules into the VM, and the suite
  # toggles the global :debug_info compiler option.
  use ExUnit.Case, async: false

  @moduledoc """
  Differential **equiv-lock**: a hand-finished Rian port compiled through
  `Rian.Beam` is checked against its Elixir oracle by `Rian.FormsEquiv`. This is
  the end of the transpile loop — `Rian.Transpile` drafts a skeleton, a human
  fills the holes, and this harness proves the result denotes the same program as
  the original Elixir.

  Two strengths of guarantee are asserted:

    * **forms-equivalence** — the normalized Erlang abstract function forms are
      equal (the general bar that also covers `if`/recursion/guards);
    * **bytecode identity** — for the portable subset the per-function BEAM `Code`
      chunk is *byte-identical*, because Rian-on-BEAM and Elixir share the same
      `:compile.forms` backend. Identical bytecode ⇒ identical runtime performance
      and memory; there is nothing left to benchmark.

  The portable subset (arithmetic, unary minus, comparison, `if`, recursion,
  multi-clause incl. guards) equiv-locks. Outside it lie:

    * `and`/`or` — Elixir inserts a defensive `badbool` runtime type-check that
      Rian's static typing makes unnecessary (asserted below as an honest
      *non*-equivalence, not masked);
    * struct/stdlib-shaped code (e.g. `lib/rian/range.ex`'s `%EIf{}`/`Map.from_struct`
      reflection) — Elixir structs are maps, Rian sums are tagged tuples, so the
      representations differ and such modules are not equiv-lockable this way.
  """

  alias Rian.FormsEquiv

  setup do
    prev = Code.get_compiler_option(:debug_info)
    Code.put_compiler_option(:debug_info, true)
    on_exit(fn -> Code.put_compiler_option(:debug_info, prev) end)
    :ok
  end

  # Compile `ex_src`/`rian_src` into the SAME module atom; return both .beam bins.
  defp both(mod_name, ex_src, rian_src) do
    mod = :"Elixir.#{mod_name}"
    :code.purge(mod)
    :code.delete(mod)
    [{^mod, ex_bin}] = Code.compile_string(ex_src)
    {:ok, ^mod, rian_bin} = Rian.Beam.compile(rian_src, mod)
    {ex_bin, rian_bin}
  end

  # The actual BEAM opcodes for one function, isolated in a minimal module so the
  # comparison is unpolluted by Elixir's injected __info__/module_info.
  defp fun_code_chunk(beam, fname) do
    fun = Enum.find(FormsEquiv.abstract_code(beam), &match?({:function, _, ^fname, _, _}, &1))
    {:function, _, name, arity, _} = fun
    forms = [{:attribute, 1, :module, :EL}, {:attribute, 1, :export, [{name, arity}]}, fun]
    {:ok, :EL, bin} = :compile.forms(forms, [:return_errors])
    {:ok, {_, [{~c"Code", c}]}} = :beam_lib.chunks(bin, [~c"Code"])
    c
  end

  describe "equiv-lock: hand-finished Rian port vs Elixir oracle" do
    test "a whole multi-function module forms-equiv-locks" do
      ex = """
      defmodule Calc do
        def double(x), do: x + x
        def neg(x), do: -x
        def abs(x), do: if x < 0, do: -x, else: x
        def max2(a, b), do: if a >= b, do: a, else: b
        def clamp(x, lo, hi), do: if x < lo, do: lo, else: (if x > hi, do: hi, else: x)
        def sum_to(n), do: if n <= 0, do: 0, else: n + sum_to(n - 1)
        def eq(a, b), do: a == b
      end
      """

      rian = """
      mod Calc do
        pub def double(x Int53) Int53 := x + x
        pub def neg(x Int53) Int53 := -x
        pub def abs(x Int53) Int53 := if x < 0 do -x else x end
        pub def max2(a Int53, b Int53) Int53 := if a >= b do a else b end
        pub def clamp(x Int53, lo Int53, hi Int53) Int53 := if x < lo do lo else if x > hi do hi else x end end
        pub def sum_to(n Int53) Int53 := if n <= 0 do 0 else n + sum_to(n - 1) end
        pub def eq(a Int53, b Int53) Bool := a == b
      end
      """

      {ex_bin, rian_bin} = both("Calc", ex, rian)
      assert FormsEquiv.equivalent?(ex_bin, rian_bin)
      # all seven user functions present (Elixir-injected ones dropped)
      assert length(FormsEquiv.normalize(ex_bin)) == 7
    end

    test "multi-clause functions with guards equiv-lock" do
      ex = """
      defmodule Sgn do
        def sign(x) when x > 0, do: 1
        def sign(x) when x < 0, do: -1
        def sign(_), do: 0
      end
      """

      rian = """
      mod Sgn do
        pub def sign(Int53) Int53
        pub def sign(x) when x > 0 := 1
        pub def sign(x) when x < 0 := -1
        pub def sign(_) := 0
      end
      """

      {ex_bin, rian_bin} = both("Sgn", ex, rian)
      assert FormsEquiv.equivalent?(ex_bin, rian_bin)
    end

    test "the portable subset emits BYTE-IDENTICAL BEAM bytecode (same perf/memory)" do
      cases = [
        {"Bc1", "defmodule Bc1 do\n  def double(x), do: x + x\nend",
         "mod Bc1 do\n  pub def double(x Int53) Int53 := x + x\nend", :double},
        {"Bc2", "defmodule Bc2 do\n  def abs(x), do: if x < 0, do: -x, else: x\nend",
         "mod Bc2 do\n  pub def abs(x Int53) Int53 := if x < 0 do -x else x end\nend", :abs},
        {"Bc3", "defmodule Bc3 do\n  def st(n), do: if n <= 0, do: 0, else: n + st(n - 1)\nend",
         "mod Bc3 do\n  pub def st(n Int53) Int53 := if n <= 0 do 0 else n + st(n - 1) end\nend", :st}
      ]

      for {name, ex, rian, fname} <- cases do
        {ex_bin, rian_bin} = both(name, ex, rian)

        assert fun_code_chunk(ex_bin, fname) == fun_code_chunk(rian_bin, fname),
               "#{fname}/_ bytecode should be byte-identical (shared :compile.forms backend)"
      end
    end
  end

  describe "the boundary is honest — divergences are reported, not masked" do
    test "`and`/`or` diverge: Elixir's defensive badbool guard vs Rian's static-typed andalso" do
      {ex_bin, rian_bin} =
        both(
          "Bool0",
          "defmodule Bool0 do\n  def both(a, b), do: a and b\nend",
          "mod Bool0 do\n  pub def both(a Bool, b Bool) Bool := a and b\nend"
        )

      # Rian, knowing a/b are Bool, drops the runtime type-check Elixir must keep.
      refute FormsEquiv.equivalent?(ex_bin, rian_bin)
      assert {:diff, [{{:both, 2}, _ex_form, _rian_form}]} = FormsEquiv.diff(ex_bin, rian_bin)
    end
  end
end

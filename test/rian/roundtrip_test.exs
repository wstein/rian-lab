defmodule Rian.RoundtripTest do
  # async: false — both BEAM backends load a throwaway module into the VM.
  use ExUnit.Case, async: false

  alias Rian.Roundtrip

  describe "run/1 — the three-step roundtrip report" do
    test "an annotated, portable module roundtrips green through both backends" do
      src = ~S'''
      defmodule Calc do
        use Rian.Ann
        @rian "pub def double(x Int53) Int53"
        def double(x), do: x + x
        @rian "pub def abs(x Int53) Int53"
        def abs(x), do: if(x < 0, do: -x, else: x)
      end
      '''

      r = Roundtrip.run(src)

      assert r.beam_direct == :ok
      assert r.beam_via_elixir == :ok
      # the two backends agree, and the roundtrip matches the original Elixir
      assert r.equiv_two_paths == :equiv
      assert r.equiv_vs_origin == :equiv
      assert r.elixir =~ "defmodule"
    end

    test "a draft that still carries a marker fails the BEAM stages (does not lie green)" do
      # a non-atom-key map literal `%{k => v}` has no `key: value` Rian spelling → a
      # TODO_PORT marker → the draft cannot compile either way. (Field access, stdlib
      # calls, and atom-key map *update* now lower; this is a residual marker class.)
      src = ~S'''
      defmodule R do
        def at(k), do: %{k => 1}
      end
      '''

      r = Roundtrip.run(src)

      assert match?({:error, _}, r.beam_direct)
      assert match?({:error, _}, r.beam_via_elixir)
      assert r.equiv_two_paths == :skipped
      assert r.equiv_vs_origin == :skipped
    end

    test "a mapped stdlib call compiles but is honestly NOT equivalent to the original" do
      # `Enum.sum` auto-maps to the Rian prelude `List.sum`, which compiles — but it
      # is a different function from Elixir's `Enum.sum`, so the roundtrip must report
      # divergence from the original, not a false `equiv`.
      src = ~S'''
      defmodule S do
        use Rian.Ann
        @rian "pub def total(xs Vec(Int53)) Int53"
        def total(xs), do: Enum.sum(xs)
      end
      '''

      r = Roundtrip.run(src)

      assert r.beam_direct == :ok
      assert r.equiv_vs_origin == :diverges
    end

    test "the harness leaves no probe module loaded in the VM" do
      Roundtrip.run("defmodule Calc do\n  def f(x), do: x\nend")
      refute :code.is_loaded(:"Elixir.RoundtripProbe")
    end

    test "the generated Rian and Elixir are emitted formatted" do
      src = ~S'''
      defmodule Calc do
        use Rian.Ann
        @rian "pub def double(x Int53) Int53"
        def double(x), do: x + x
      end
      '''

      r = Roundtrip.run(src)

      # idempotent under each language's formatter ⇒ already formatted
      assert r.rian == Rian.Format.format(r.rian)
      assert r.elixir == IO.iodata_to_binary(Code.format_string!(r.elixir)) <> "\n"
    end
  end

  describe "end-to-end — a green roundtrip yields a working, test-passing module" do
    test "the roundtripped BEAM loads and computes the same as the Elixir oracle" do
      src = ~S'''
      defmodule Arith do
        use Rian.Ann
        @rian "pub def double(x Int53) Int53"
        def double(x), do: x + x
        @rian "pub def sum_to(n Int53) Int53"
        def sum_to(n), do: if(n <= 0, do: 0, else: n + sum_to(n - 1))
      end
      '''

      # green through both backends, and equivalent to the original
      r = Roundtrip.run(src)
      assert r.beam_direct == :ok
      assert r.beam_via_elixir == :ok
      assert r.equiv_vs_origin == :equiv

      # the Rian-compiled bytecode is not just compilable but *correct*: load it and
      # run the functions against the values the Elixir oracle would produce.
      rian = Rian.Transpile.transpile(src)
      {:ok, mod, bin} = Rian.Beam.compile(rian, :"Elixir.ArithProbe")
      :code.load_binary(mod, ~c"ArithProbe.beam", bin)

      try do
        assert mod.double(21) == 42
        assert mod.sum_to(5) == 15
      after
        :code.purge(mod)
        :code.delete(mod)
      end
    end

    test "a real lib/rian module (ir.ex — the Core IR vocabulary) compiles on both backends" do
      r = Roundtrip.run(File.read!("lib/rian/ir.ex"))

      assert r.beam_direct == :ok
      assert r.beam_via_elixir == :ok
      # the two Rian backends agree; the roundtrip honestly diverges from the
      # original Elixir because Rian lowers a struct to a tagged map, not an Elixir
      # `%struct{}` with its injected `__struct__/0,1`.
      assert r.equiv_two_paths == :equiv
      assert r.equiv_vs_origin == :diverges
    end

    test "a nested-module source roundtrips ALL modules (no silent drop)" do
      # Rian modules are flat, so the transpiler hoists `Inner` to a sibling
      # top-level `mod`; the harness must roundtrip both `a/1` and `b/1`, not just
      # the first module.
      src = ~S'''
      defmodule Outer do
        use Rian.Ann
        @rian "pub def a(x Int53) Int53"
        def a(x), do: x + 1

        defmodule Inner do
          use Rian.Ann
          @rian "pub def b(y Int53) Int53"
          def b(y), do: y * 2
        end
      end
      '''

      r = Roundtrip.run(src)
      assert r.beam_direct == :ok
      assert r.beam_via_elixir == :ok
      assert r.equiv_two_paths == :equiv
      # both modules survive the roundtrip — the regenerated Elixir defines each
      assert r.elixir =~ "def a(x)"
      assert r.elixir =~ "def b(y)"
    end

    test "named construction agrees across backends (Rian.Lower ↔ Rian.Beam parity)" do
      # `Pt(x: 1, y: 2)` is a struct construction; both backends must lower it to the
      # same `__struct__`-tagged map, so the two BEAM binaries are forms-equivalent
      # even though `Pt` is not declared in this module.
      src = ~S'''
      defmodule Mk do
        use Rian.Ann
        @rian "pub def origin() Pt"
        def origin, do: %Pt{x: 0, y: 0}
      end
      '''

      r = Roundtrip.run(src)
      assert r.beam_direct == :ok
      assert r.beam_via_elixir == :ok
      assert r.equiv_two_paths == :equiv
    end
  end
end

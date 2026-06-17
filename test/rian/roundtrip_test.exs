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
      # `Map.from_struct` reflection has no Rian image → a TODO_PORT marker → the
      # draft cannot compile either way.
      src = ~S'''
      defmodule R do
        def fields(s), do: Map.from_struct(s)
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
  end
end

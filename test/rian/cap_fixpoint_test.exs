defmodule Rian.CapFixpointTest do
  # async: false — loads a real module into the VM via :code.load_binary.
  use ExUnit.Case, async: false

  alias Rian.{Beam, Capability}

  # Self-hosting fixpoint (ADR-0063) for the **capability checker** stage: a
  # Rian-written capability→Rust lowering (examples/rian/selfhost_cap.rian),
  # compiled to real `.beam`, diffed against the reference `Rian.Capability`.
  #
  #   * `rust_param/2` — capability + type -> Rust parameter spelling — must equal
  #     `Rian.Capability.rust_param/2` over the slice.
  #   * `beam_legal/1` — the portable-core legality (`ref` rejected, P5) — must
  #     agree with the reference `beam_legal!/1` (which raises on `ref`).
  #
  # Slice: the scalar `Copy` types, `String`, one level of `Vec(...)`, and a bare
  # nominal type. The remaining vocabulary (deep generics, `Int`, the BEAM
  # linearity check) is the `:partial` tail (ADR-0063 / docs/self-host-status.md).

  setup_all do
    {:ok, mod} = Beam.load(File.read!("examples/rian/selfhost_cap.rian"), :rian_cap_fixpoint)
    {:ok, mod: mod}
  end

  @caps [:iso, :val, :ref, :tag]

  # {reference source-type string, the port's `Ty` injection}
  @types [
    {"Int53", :t_int53},
    {"Int32", :t_int32},
    {"Bool", :t_bool},
    {"Float64", :t_float64},
    {"String", :t_str},
    {"Vec(Int53)", :t_vec_int53},
    {"Vec(String)", :t_vec_str},
    {"Foo", {:t_nom, "Foo"}}
  ]

  describe "self-hosting capability fixpoint — Rian lowering vs Rian.Capability" do
    test "rust_param agrees with Rian.Capability.rust_param over the whole matrix", %{mod: mod} do
      for cap <- @caps, {tstr, tport} <- @types do
        assert mod.rust_param(cap, tport) == Capability.rust_param(cap, tstr),
               "diverged on #{cap} #{tstr}"
      end
    end

    test "beam_legal agrees with the reference beam_legal!/1 (ref rejected)", %{mod: mod} do
      for cap <- @caps do
        ref_legal =
          try do
            Capability.beam_legal!(cap)
            true
          rescue
            _ -> false
          end

        assert mod.beam_legal(cap) == ref_legal, "beam_legal diverged on #{cap}"
      end
    end
  end

  describe "teeth — the lowering is capability- and type-sensitive (not a lookup constant)" do
    test "val borrows a non-Copy type but passes a Copy scalar by value", %{mod: mod} do
      assert mod.rust_param(:val, :t_str) == "&str"
      assert mod.rust_param(:val, :t_int53) == "i64"
      # iso owns the same String that val borrows — capability changes the answer.
      refute mod.rust_param(:iso, :t_str) == mod.rust_param(:val, :t_str)
    end

    test "ref emits the BEAM-illegal &mut form", %{mod: mod} do
      assert mod.rust_param(:ref, :t_int53) == "&mut i64"
      refute mod.rust_param(:ref, :t_int53) == mod.rust_param(:tag, :t_int53)
    end

    test "only ref is BEAM-illegal — the portable core is val/iso/tag (P5)", %{mod: mod} do
      refute mod.beam_legal(:ref)
      assert mod.beam_legal(:iso) and mod.beam_legal(:val) and mod.beam_legal(:tag)
    end

    test "the type changes the spelling (not constant per capability)", %{mod: mod} do
      refute mod.rust_param(:iso, :t_str) == mod.rust_param(:iso, :t_vec_int53)
      refute mod.rust_param(:tag, :t_int53) == mod.rust_param(:tag, {:t_nom, "Foo"})
    end
  end
end

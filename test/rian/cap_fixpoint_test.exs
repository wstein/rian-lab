defmodule Rian.CapFixpointTest do
  # async: false — loads a real module into the VM via :code.load_binary.
  use ExUnit.Case, async: false

  alias Rian.{Beam, Capability, TypeStr}

  # Self-hosting fixpoint (ADR-0063) for the **capability checker** stage: a
  # Rian-written capability→Rust lowering (compiler/cap.rian),
  # compiled to real `.beam`, diffed against the reference `Rian.Capability` over
  # the FULL type vocabulary — every `Copy` width, `String`, nominal types, nested
  # `Vec(...)`, and parametric generics `Name(A, B, …)`, across all four
  # capabilities, plus the reference quirk that `val` of a generic borrows the
  # unlowered source spelling.
  #
  # The capability stage maps cap+type→Rust; it consumes a type in structured form
  # (`Ty`). `to_ty/1` here is the type-parser's job (tokenising `"Vec(Int32)"` →
  # `TVec(TScalar("Int32"))`) — the reference re-parses the string only because the
  # IR stores types as strings; the mapping itself is fully self-hosted.

  setup_all do
    {:ok, mod} = Beam.load(File.read!("compiler/cap.rian"), :rian_cap_fixpoint)
    {:ok, mod: mod}
  end

  @copy ~w(Int8 Int16 Int32 Int64 Int128 UInt8 UInt16 UInt32 UInt64 UInt128
           Int53 Float32 Float64 Bool Char)

  # tokenise a type string into the port's structured `Ty` (the type-parser's job).
  defp to_ty(s) do
    cond do
      s in @copy ->
        {:t_scalar, s}

      s == "String" ->
        :t_string

      m = Regex.run(~r/^([A-Za-z_]\w*)\((.*)\)$/, s) ->
        [_, name, inner] = m

        if name == "Vec",
          do: {:t_vec, to_ty(inner)},
          else: {:t_gen, name, Enum.map(TypeStr.split_top_commas(inner), &to_ty/1), s}

      true ->
        {:t_nom, s}
    end
  end

  @caps [:iso, :val, :ref, :tag]

  # the full type vocabulary: every Copy width, String, nominal, nested Vec, and
  # parametric generics (incl. nesting and a generic that borrows unlowered).
  @types @copy ++
           [
             "String",
             "Foo",
             "Vec(Int32)",
             "Vec(String)",
             "Vec(Foo)",
             "Vec(Vec(Int8))",
             "Option(Int64)",
             "Pair(Int32, String)",
             "Vec(Option(Int64))",
             "Map(String, Vec(Int64))"
           ]

  describe "self-hosting capability fixpoint — Rian lowering vs Rian.Capability (full)" do
    test "rust_param agrees with Rian.Capability.rust_param over the WHOLE matrix", %{mod: mod} do
      for cap <- @caps, t <- @types do
        assert mod.rust_param(cap, to_ty(t)) == Capability.rust_param(cap, t),
               "diverged on #{cap} #{t}"
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

  describe "teeth — the full mapping is capability- and structure-sensitive" do
    test "val borrows non-Copy but passes Copy by value; every width maps", %{mod: mod} do
      assert mod.rust_param(:val, to_ty("String")) == "&str"
      assert mod.rust_param(:val, to_ty("Int53")) == "i64"
      assert mod.rust_param(:val, to_ty("UInt128")) == "u128"
      refute mod.rust_param(:iso, to_ty("String")) == mod.rust_param(:val, to_ty("String"))
    end

    test "nested generics lower recursively under iso/owned", %{mod: mod} do
      assert mod.rust_param(:iso, to_ty("Vec(Vec(Int8))")) == "Vec<Vec<i8>>"
      assert mod.rust_param(:iso, to_ty("Option(Int64)")) == "Option<i64>"
      assert mod.rust_param(:iso, to_ty("Map(String, Vec(Int64))")) == "Map<String, Vec<i64>>"
    end

    test "the reference quirk: val of a generic borrows the UNLOWERED spelling", %{mod: mod} do
      assert mod.rust_param(:val, to_ty("Option(Int64)")) == "&Option(Int64)"
      # ...whereas iso lowers it — the two must differ.
      refute mod.rust_param(:val, to_ty("Option(Int64)")) ==
               mod.rust_param(:iso, to_ty("Option(Int64)"))
    end

    test "ref emits &mut and only ref is BEAM-illegal (P5)", %{mod: mod} do
      assert mod.rust_param(:ref, to_ty("Int53")) == "&mut i64"
      refute mod.beam_legal(:ref)
      assert mod.beam_legal(:iso) and mod.beam_legal(:val) and mod.beam_legal(:tag)
    end
  end

  # === reference-completeness ledger (selfhost_cap vs Rian.Capability) ==========
  # The matrix test above already proves parity over @caps × @types; this is the
  # explicit type-category checklist with teeth + a coverage count. The port
  # reproduces the WHOLE mapping matrix (the linearity/use-once check and the
  # type-string tokenizer are intentionally a different stage, not the mapping).
  defp cap_covers?(mod, t) do
    Enum.all?([:iso, :val, :ref, :tag], fn c ->
      mod.rust_param(c, to_ty(t)) == Capability.rust_param(c, t)
    end)
  rescue
    _ -> false
  catch
    _, _ -> false
  end

  @cap_categories [
    {"Copy scalar", "Int53", true},
    {"String", "String", true},
    {"nominal", "Foo", true},
    {"Vec(scalar)", "Vec(Int32)", true},
    {"nested Vec", "Vec(Vec(Int8))", true},
    {"generic + val-quirk", "Option(Int64)", true},
    {"Map(K, V)", "Map(String, Int64)", true}
  ]

  describe "capability completeness ledger (selfhost_cap vs Rian.Capability)" do
    test "every type category's ported? flag matches reality (all 4 caps)", %{mod: mod} do
      drift =
        for {name, t, ported?} <- @cap_categories, cap_covers?(mod, t) != ported? do
          "#{name}: ported?=#{ported?} but selfhost_cap " <>
            "#{if cap_covers?(mod, t), do: "REPRODUCES", else: "does NOT reproduce"} Rian.Capability"
        end

      assert drift == [], "capability completeness ledger drifted:\n" <> Enum.join(drift, "\n")
    end

    test "type-category coverage is measured (the full matrix is locked above)" do
      total = length(@cap_categories)
      ported = Enum.count(@cap_categories, fn {_, _, p} -> p end)
      IO.puts("\n  selfhost_cap completeness: #{ported}/#{total} type categories (×4 caps)")
      assert ported == total
    end
  end
end

defmodule Rian.RustTyFixpointTest do
  # async: false — loads a real module into the VM via :code.load_binary.
  use ExUnit.Case, async: false

  alias Rian.{Beam, Capability, TypeStr}

  # Self-hosting fixpoint (ADR-0063) — slice 1 of the whole-module Rust backend
  # port: **parametric type rendering, regex-free**. `Rian.Lower` renders a type to
  # owned Rust (`Capability.owned`) then splices `<K, V>` onto each parametric name
  # via a `Regex` (`rustify_parametric`). Rian has no regex, so the port models the
  # type STRUCTURALLY (`Ty` = `TName | TApp`) and substitutes by recursion
  # (`inst_ty`), then renders (`render_ty`).
  #
  # `instantiate(type) then render` is exactly `owned(type-with-the-parametric-name-
  # applied)`: applying `Pair` to `[K, V]` is the same as writing `Pair(K, V)` and
  # rendering it. So the port's `render_inst(unapplied, pinst)` is diffed against the
  # PUBLIC `Capability.owned(applied)` — the real base renderer + the splice it
  # post-processes — with no private function and no hand-rolled oracle.

  setup_all do
    {:ok, mod} = Beam.load(File.read!("examples/rian/selfhost_rust.rian"), :rian_rust_ty_fixpoint)
    {:ok, mod: mod}
  end

  # a Rian type string -> the port's `Ty` injection (`Vec(Pair)` ->
  # {:t_app, "Vec", [{:t_name, "Pair"}]}).
  defp ty(s) do
    case Regex.run(~r/^([A-Za-z_]\w*)\((.*)\)$/, String.trim(s)) do
      [_, name, inner] -> {:t_app, name, inner |> TypeStr.split_top_commas() |> Enum.map(&ty/1)}
      _ -> {:t_name, String.trim(s)}
    end
  end

  # a pinst spec [{"Pair", ["K", "V"]}] -> the port's `Vec(Inst)` injection.
  defp inj_pinst(specs),
    do: Enum.map(specs, fn {name, args} -> {:inst, name, Enum.map(args, &ty/1)} end)

  defp ported(mod, unapplied, pinst), do: mod.render_inst(ty(unapplied), inj_pinst(pinst))

  # {unapplied Rian type, pinst spec, the equivalent *applied* type — the oracle fed
  # to the real `Capability.owned/1`}.
  @corpus [
    # parametric instantiation with the type's own params (the generic case)
    {"Vec(Pair)", [{"Pair", ["K", "V"]}], "Vec(Pair(K, V))"},
    {"Pair", [{"Pair", ["K", "V"]}], "Pair(K, V)"},
    {"Option(Pair)", [{"Pair", ["K", "V"]}], "Option(Pair(K, V))"},
    {"Vec(Vec(Pair))", [{"Pair", ["K", "V"]}], "Vec(Vec(Pair(K, V)))"},
    {"Box", [{"Box", ["T"]}], "Box(T)"},
    # concrete instantiation — the scalar map fires on the args (Int53 -> i64)
    {"Pair", [{"Pair", ["Int53", "String"]}], "Pair(Int53, String)"},
    {"Vec(Pair)", [{"Pair", ["String", "Int64"]}], "Vec(Pair(String, Int64))"},
    # no instantiation — the pure owned renderer over scalars/containers/nesting
    {"Vec(Int64)", [], "Vec(Int64)"},
    {"Vec(Vec(Int64))", [], "Vec(Vec(Int64))"},
    {"Map(String, Vec(Int64))", [], "Map(String, Vec(Int64))"},
    {"Int53", [], "Int53"},
    {"Float64", [], "Float64"},
    {"String", [], "String"}
  ]

  describe "self-hosting Rust type-render fixpoint — Rian vs Capability.owned (no regex)" do
    test "render_inst equals Capability.owned of the applied type, term-for-term", %{mod: mod} do
      for {unapplied, pinst, applied} <- @corpus do
        assert ported(mod, unapplied, pinst) == Capability.owned(applied),
               "type rendering diverged on #{inspect(unapplied)} + #{inspect(pinst)}"
      end
    end
  end

  describe "teeth — the scalar map, nesting, and the splice are real" do
    test "the @copy scalar map fires (Int53 -> i64), not passthrough", %{mod: mod} do
      assert ported(mod, "Int53", []) == "i64"
      refute ported(mod, "Int53", []) == "Int53"
      assert ported(mod, "UInt128", []) == "u128"
      # a non-Copy nominal / tvar passes through
      assert ported(mod, "String", []) == "String"
    end

    test "nesting and arity are preserved structurally", %{mod: mod} do
      assert ported(mod, "Vec(Vec(Int64))", []) == "Vec<Vec<i64>>"
      assert ported(mod, "Map(String, Vec(Int64))", []) == "Map<String, Vec<i64>>"
    end

    test "instantiation splices the args and discriminates from the unapplied name", %{mod: mod} do
      assert ported(mod, "Pair", [{"Pair", ["K", "V"]}]) == "Pair<K, V>"
      # without the pinst, the same name renders bare — the splice is doing real work
      assert ported(mod, "Pair", []) == "Pair"
      refute ported(mod, "Pair", [{"Pair", ["K", "V"]}]) == ported(mod, "Pair", [])
    end
  end
end

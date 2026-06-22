defmodule Rian.ShadowPortTest do
  # async: false — loads a real BEAM module into the VM.
  use ExUnit.Case, async: false

  @moduledoc """
  `rian/src/shadow.rian` is the self-host port of `Rian.Shadow` (the `:=`
  capture-avoiding rename, ADR-0034). Its AST walk was rewritten **reflection-free**
  (no `Map.from_struct`/`is_struct`; `Map.new`→`Dict.from_list`, `Map.delete`→a
  put-identity) so it reaches the non-BEAM backends. These verify the rename logic
  on Rian's own self-hosted Core representation and that it now compiles to JS.
  """

  # `rian/src/shadow.rian` is gitignored self-host output (the hand-ported,
  # reflection-free pass) and is NOT in version control, so it is absent in a clean
  # checkout / CI. Skip rather than fail `setup_all` when it is missing — the same
  # no-op-without-its-input contract the toolchain tests use (ADR-0026). Generate +
  # hand-port it locally to run these (see commit a696ac6).
  @port_src "rian/src/shadow.rian"
  unless File.exists?(@port_src) do
    @moduletag skip: "#{@port_src} not present (gitignored self-host output)"
  end

  defp id(n), do: %{__struct__: :e_id, name: n}
  defp num(s), do: %{__struct__: :e_num, text: s}
  defp val(%{name: n}), do: n
  defp val(%{text: t}), do: t

  setup_all do
    {:ok, port} = Rian.Beam.load(File.read!("rian/src/shadow.rian"), :"Elixir.RianShadowPort")
    fresh = fn base, count -> base <> "$" <> Integer.to_string(count) end
    {:ok, port: port, fresh: fresh}
  end

  test "a same-scope `:=` rebind is renamed; references resolve to the in-force binding", %{
    port: port,
    fresh: fresh
  } do
    # x := 1 ; x := x ; z := x
    out =
      port.dedup(
        [{:bind, "x", num("1")}, {:bind, "x", id("x")}, {:bind, "z", id("x")}],
        [],
        fresh
      )

    # first x stays; the rebind becomes x$1 and resolves its value to the first x;
    # z then resolves to the renamed x$1 (the binding in force at its position).
    assert Enum.map(out, fn {:bind, n, e} -> {n, val(e)} end) ==
             [{"x", "1"}, {"x$1", "x"}, {"z", "x$1"}]
  end

  test "a `:=` rebinding a clause parameter renames from the first occurrence", %{
    port: port,
    fresh: fresh
  } do
    # the param `p` seeds the version map, so `p := p` is a rebind (renamed)
    assert [{:bind, "p$1", _}] = port.dedup([{:bind, "p", id("p")}], ["p"], fresh)
  end

  test "a nested EBlock opens a fresh scope (rebinds inside it are independent)", %{
    port: port,
    fresh: fresh
  } do
    inner = %{__struct__: :e_block, stmts: [{:bind, "x", num("9")}]}
    # outer x := 1 ; y := <block that rebinds x> — the inner x is its own scope
    out = port.dedup([{:bind, "x", num("1")}, {:bind, "y", inner}], [], fresh)
    [{:bind, "x", _}, {:bind, "y", blk}] = out
    assert [{:bind, "x", _}] = blk.stmts
  end

  test "the reflection-free walk reaches JS (was off :js via Map.from_struct)" do
    js = Rian.JS.compile(File.read!("rian/src/shadow.rian"))
    assert js =~ "function dedup("
    refute js =~ "from_struct"
  end
end

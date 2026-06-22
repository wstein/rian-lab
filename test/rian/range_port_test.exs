defmodule Rian.RangePortTest do
  # async: false — loads a real BEAM module into the VM.
  use ExUnit.Case, async: false

  @moduledoc """
  `rian/src/range.rian` is a self-host port of `Rian.Range` (ADR-0036) whose AST
  walk was rewritten **reflection-free** (no `Map.from_struct`/`is_struct`) so it
  reaches the non-BEAM backends. These tests verify (1) the rewrite is behaviourally
  correct on Rian's *own* Core representation — the snake-tagged structs the
  self-hosted `core.rian` produces, NOT the host `Rian.Core.*` Elixir structs — and
  (2) it now compiles to JS (the portability the reflection-free walk buys).
  """

  # `rian/src/range.rian` is gitignored self-host output (the hand-ported,
  # reflection-free pass) and is NOT in version control, so it is absent in a clean
  # checkout / CI. Skip rather than fail `setup_all` when it is missing — the same
  # no-op-without-its-input contract the toolchain tests use (ADR-0026). Generate +
  # hand-port it locally to run these (see commit fb40c96).
  @port_src "rian/src/range.rian"
  unless File.exists?(@port_src) do
    @moduletag skip: "#{@port_src} not present (gitignored self-host output)"
  end

  # a Core node in Rian's self-hosted convention (`%{__struct__: :e_*, …}`), the
  # shape `range.rian`'s own constructors build and its clause heads match.
  defp e_id(name), do: %{__struct__: :e_id, name: name, type: nil}
  defp dot(head, name), do: %{__struct__: :e_dot, head: head, name: name, type: nil}
  defp call(fun, args), do: %{__struct__: :e_call, fun: fun, args: args, type: nil}
  defp of_call(name, arg), do: call(dot(e_id(name), "of"), [arg])

  setup_all do
    {:ok, port} = Rian.Beam.load(File.read!("rian/src/range.rian"), :"Elixir.RianRangePort")
    tbl = port.table([%Rian.IR.Range{name: "Digit", lo: 0, hi: 9, base: 0}])
    {:ok, port: port, tbl: tbl}
  end

  test "table builds a name -> {lo, hi, base} tuple map (portable, no map pattern)", %{tbl: tbl} do
    assert tbl == %{"Digit" => {0, 9, 0}}
  end

  test "expand_of rewrites a declared `Name.of(n)` into an `EIf` bounds check", %{
    port: port,
    tbl: tbl
  } do
    out = port.expand_of(of_call("Digit", e_id("y")), tbl)
    assert out.__struct__ == :e_if
    # the `:ok` branch (then) carries the original argument unchanged
    assert out.then.__struct__ == :e_tuple
    [ok_atom, arg] = out.then.elems
    # range constructs `EAtom(name: "ok")` (no `type` field set)
    assert ok_atom == %{__struct__: :e_atom, name: "ok"}
    assert arg == e_id("y")
  end

  test "an undeclared `Name.of(n)` is left a call; nested `Name.of` still rewrites", %{
    port: port,
    tbl: tbl
  } do
    # `Other.of(Digit.of(y))` — Other is not a range, so it stays a call, but the
    # nested Digit.of(y) argument is still expanded (the walk recurses).
    out = port.expand_of(of_call("Other", of_call("Digit", e_id("y"))), tbl)
    assert out.__struct__ == :e_call
    [inner] = out.args
    assert inner.__struct__ == :e_if
  end

  test "the reflection-free walk reaches JS (was off :js via Map.from_struct)" do
    js = Rian.JS.compile(File.read!("rian/src/range.rian"))
    assert js =~ "function expand_of("
    # no reflective host call leaked into the emitted JS
    refute js =~ "from_struct"
  end
end

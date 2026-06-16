defmodule Rian.ComposeProtocolFixpointTest do
  # async: false — loads the verified ports + the driver into the VM.
  use ExUnit.Case, async: false
  alias Rian.Beam

  # P3 — the self-built compiler now EMITS protocols (ADR-0042 §3). `compile_module`
  # desugars every `protocol`/`impl` into its guarded BEAM dispatcher + mangled impl
  # functions (`Decl.expand_protocols_src`, re-parsed through the same front end) and
  # emits them alongside the user functions. The lexer gained the `protocol`/`impl`
  # keywords; the variable-application pass exempts the dispatcher's guard BIFs
  # (`is_integer`/`is_binary`/…) so they stay legal in a `when` guard. This unblocks
  # the protocol-bound type gate (bounds_bad) — a bounded-generic program now compiles
  # AND runs on the self-built compiler.

  setup_all do
    for {f, m} <- [
          {"lexer_v2", "LexerV2"},
          {"decl", "Decl"},
          {"beam", "Beam"},
          {"exhaust", "Exhaust"},
          {"cap", "Cap"},
          {"checker", "Checker"}
        ] do
      {:ok, _} = Beam.load(File.read!("compiler/#{f}.rian"), :"Elixir.#{m}")
    end

    {:ok, drv} = Beam.load(File.read!("compiler/compose_real_sum.rian"), :rian_protocol_emit)
    {:ok, drv: drv}
  end

  defp uniq(prefix), do: :"#{prefix}_#{System.unique_integer([:positive])}"

  @show """
  protocol Show do
    def show(self Self) String
  end
  """

  describe "the self-built compiler emits protocol dispatchers + impl functions" do
    test "a single-impl protocol dispatches and runs", %{drv: drv} do
      src =
        @show <>
          "\nimpl Show for Int53 do\n  def show(x) := \"int\"\nend\n\ndef go() String := show(5)"

      m = drv.build(src, uniq(:Proto1))
      assert m.go() == "int"
    end

    test "multiple impls dispatch by the argument's runtime type", %{drv: drv} do
      src =
        @show <>
          "\nimpl Show for Int53 do\n  def show(x) := \"int\"\nend\n" <>
          "\nimpl Show for String do\n  def show(x) := \"str\"\nend\n" <>
          "\ndef gi() String := show(5)\ndef gs() String := show(\"hi\")"

      m = drv.build(src, uniq(:Proto2))
      assert m.gi() == "int"
      assert m.gs() == "str"
    end

    test "an impl method body that uses its argument runs", %{drv: drv} do
      src =
        @show <>
          "\nimpl Show for Int53 do\n  def show(x) := __prim_int_to_string(x)\nend\n\ndef go() String := show(42)"

      m = drv.build(src, uniq(:Proto3))
      assert m.go() == "42"
    end
  end
end

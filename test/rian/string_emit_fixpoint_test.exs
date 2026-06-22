defmodule Rian.StringEmitFixpointTest do
  @moduledoc """
  String-emit fixpoint with teeth (ADR-0063 §4 — Maya's "string-emit
  fragility" critique). The self-hosting lexer emits no string literals, so emitter
  escaping (quotes, backslashes, control chars, unicode, `$`) was *latent, untested* —
  yet a compiler-in-Rian emits code full of string literals, where a single bad escape
  silently miscompiles.

  This locks it: a `def s() String := "<tricky>"` is compiled and **run** on the BEAM,
  and (where the toolchains exist) cross-checked on JS via `node` and Rust via `rustc`.
  The runtime string must equal the source string round-tripped through the lexer +
  each emitter, **by codepoint**, on every target — so an emitter that mis-escapes
  fails the diff. The **teeth**: escapes are processed, not passed through literally
  (a real newline is one codepoint, not the two of `\\n`).
  """
  use ExUnit.Case, async: false

  alias Rian.{Beam, JS}

  # {Rian source body (escapes UN-processed via ~S), expected runtime value (escapes
  # processed by Elixir)}. The round-trip: the Rian lexer reads the source escape, an
  # emitter re-emits it, and running it must reproduce the expected value.
  @corpus [
    {~S|"hi"|, "hi"},
    {~S|"a\"b"|, ~s|a"b|},
    {~S|"a\\b"|, ~S|a\b|},
    {~S|"a\tb"|, "a\tb"},
    {~S|"a\nb"|, "a\nb"},
    {~S|"caf\u{e9}"|, "café"},
    {~S|"a$b"|, "a$b"},
    {~S|"\t\"$\\"|, "\t\"$\\"}
  ]

  defp cps(s), do: String.to_charlist(s)

  describe "BEAM string emission round-trips every escape" do
    test "the compiled runtime string equals the source string for each escape" do
      for {body, expected} <- @corpus do
        {:ok, m} =
          Beam.load("pub def s() String := #{body}", :"se_#{System.unique_integer([:positive])}")

        assert m.s() == expected, "BEAM mis-emitted #{body}"
      end
    end

    test "teeth — an escape is processed, not passed through literally" do
      {:ok, m} = Beam.load(~S|pub def s() String := "a\nb"|, :se_teeth_nl)
      # a real newline: 3 bytes (`a`, 0x0A, `b`) — NOT the 4-char literal `a\nb`
      assert byte_size(m.s()) == 3
      assert m.s() == "a\nb"
      refute m.s() == ~S|a\nb|

      {:ok, m2} = Beam.load(~S|pub def s() String := "a\\b"|, :se_teeth_bs)
      # a single literal backslash (`\`), not an escape sequence
      assert byte_size(m2.s()) == 3
      assert m2.s() == ~S|a\b|
    end
  end

  describe "cross-target string emission agrees by codepoint (JS / Rust)" do
    test "node-run JS strings match the BEAM/expected codepoints" do
      case System.find_executable("node") do
        nil ->
          :ok

        node ->
          for {body, expected} <- @corpus do
            js = JS.compile("pub def s() String := #{body}")
            path = Path.join(System.tmp_dir!(), "se_#{System.unique_integer([:positive])}.mjs")

            File.write!(
              path,
              js <> "\nconsole.log([...s()].map(c => c.codePointAt(0)).join(\",\"));\n"
            )

            {out, 0} = System.cmd(node, [path])
            File.rm(path)
            got = out |> String.trim() |> parse_cps()
            assert got == cps(expected), "JS mis-emitted #{body}: #{inspect(got)}"
          end
      end
    end

    @tag :rust
    test "rustc-run Rust strings match the BEAM/expected codepoints" do
      case System.find_executable("rustc") do
        nil ->
          :ok

        rustc ->
          for {body, expected} <- @corpus do
            rust = Rian.Lower.rust_program(Rian.Decl.parse("pub def s() String := #{body}"))
            path = Path.join(System.tmp_dir!(), "se_#{System.unique_integer([:positive])}.rs")
            bin = String.trim_trailing(path, ".rs")

            File.write!(
              path,
              rust <>
                "\nfn main() { println!(\"{}\", s().chars().map(|c| (c as u32).to_string()).collect::<Vec<_>>().join(\",\")); }"
            )

            {_o, code} =
              System.cmd(rustc, ["--edition", "2021", "-A", "warnings", path, "-o", bin],
                stderr_to_stdout: true
              )

            assert code == 0, "Rust failed to compile for #{body}"
            {out, 0} = System.cmd(bin, [])
            File.rm(path)
            File.rm(bin)
            got = out |> String.trim() |> parse_cps()
            assert got == cps(expected), "Rust mis-emitted #{body}: #{inspect(got)}"
          end
      end
    end
  end

  defp parse_cps(""), do: []
  defp parse_cps(s), do: s |> String.split(",") |> Enum.map(&String.to_integer/1)
end

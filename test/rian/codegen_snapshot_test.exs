defmodule Rian.CodegenSnapshotTest do
  use ExUnit.Case, async: true

  # Golden-file SNAPSHOT of the three text emitters — Elixir (`Rian.Lower`), Rust
  # (`Rian.Lower.rust_program`), and ECMAScript (`Rian.JS`) — over a corpus of Rian
  # programs under `test/fixtures/codegen/`. Each `<name>.rian` has a `<name>.ex` /
  # `.rs` / `.js` golden alongside; this regenerates and asserts the output is
  # byte-identical, so any emitter change that alters generated code fails the test
  # with a reviewable diff (a regression guard, not an oracle comparison).
  #
  # A golden's PRESENCE declares that (program, target) pair is expected to compile;
  # an emitter that raises `Unsupported` for a program simply has no golden for that
  # target (and the test flags it if a golden later regresses to raising).
  #
  # Regenerate after an INTENTIONAL emitter change:
  #     SNAPSHOT=1 mix test test/rian/codegen_snapshot_test.exs
  @dir Path.expand("../fixtures/codegen", __DIR__)
  @targets [ex: "ex", rs: "rs", js: "js"]
  @snapshot System.get_env("SNAPSHOT") == "1"

  # the Elixir golden is `mix format`-ed so it stays stable under the repo's formatter
  # (the emitter itself produces unformatted single-line text; format makes it readable
  # AND idempotent, so a `mix format` pass over the fixture never drifts the snapshot).
  defp gen(src, :ex) do
    Rian.Decl.compile(src)
    |> Enum.map_join("\n", fn {_, o} -> o[:elixir] || "" end)
    |> Code.format_string!()
    |> IO.iodata_to_binary()
  end

  defp gen(src, :rs), do: Rian.Lower.rust_program(Rian.Decl.parse(src))
  defp gen(src, :js), do: Rian.JS.compile(src)

  defp emit(src, tgt) do
    {:ok, gen(src, tgt)}
  rescue
    e -> {:unsupported, Exception.message(e)}
  end

  for path <- Path.wildcard(Path.join(@dir, "*.rian")) |> Enum.sort() do
    @name Path.basename(path, ".rian")
    @path path
    test "codegen snapshot — #{Path.basename(path, ".rian")}" do
      src = File.read!(@path)

      for {tgt, ext} <- @targets do
        golden = Path.join(@dir, "#{@name}.#{ext}")
        out = emit(src, tgt)

        if @snapshot do
          case out do
            {:ok, code} -> File.write!(golden, code <> "\n")
            {:unsupported, _} -> File.rm(golden)
          end
        else
          if File.exists?(golden) do
            expected = File.read!(golden) |> String.trim_trailing()

            case out do
              {:ok, code} ->
                assert code == expected,
                       "#{@name}.#{ext} drifted from its snapshot — run `SNAPSHOT=1 mix test` to update if intentional"

              {:unsupported, msg} ->
                flunk(
                  "#{@name}.#{ext}: the emitter now raises (#{msg}) but a golden snapshot exists"
                )
            end
          end
        end
      end
    end
  end
end

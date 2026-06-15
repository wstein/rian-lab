defmodule Rian.ShowFloatTest do
  # async: false — loads a module into the VM via Rian.Beam.load.
  use ExUnit.Case, async: false

  # ADR-0069 Float64 unlock, step 2: `Show.float` is the canonical ECMAScript
  # `Number::toString` (ECMA-262 §7.1.12.1), written ONCE in portable Rian over
  # `__prim_float_repr`. This proves it: compile it to BEAM and JS, run over a
  # corpus, and assert each output equals JS `String(x)` — the ECMAScript reference.
  # The BEAM match is the real proof (a different engine reproducing ECMA exactly).
  #
  # Byte-identical on **all four** targets: BEAM, JS, Rust, and the JVM. The JVM's
  # `__prim_float_repr` searches for the true shortest round-tripping decimal rather
  # than trusting `Double.toString` (JLS-pinned to a non-shortest form for the tiniest
  # denormals), so the denormal extremes (`5e-324`, `1e-323`) now match too — no caveat.

  @src File.read!("examples/rian/stdlib_show.rian")

  # curated corpus: integer-valued, decimals, signs, ±0, the exponent thresholds
  # (1e21 / 1e-7 where ECMA switches to scientific), subnormals, and the denormal
  # extremes that exercise the shortest-round-trip search on every target.
  @corpus [
    1.0,
    42.0,
    100.0,
    0.1,
    0.5,
    2.5,
    3.14,
    0.3,
    1.1,
    123_456.789,
    -2.5,
    -0.0,
    0.0,
    1.0e20,
    1.0e21,
    1.0e22,
    9.999e20,
    1.0e-6,
    1.0e-7,
    0.000001,
    1.5e300,
    1.0e-300,
    1.7976931348623157e308,
    5.0e-324,
    1.0e-323,
    9.9e-324,
    100_000_000_000_000_000_000.0
  ]

  # the ECMAScript reference: JS `String(x)` (= Number::toString) via node.
  defp reference do
    case System.find_executable("node") do
      nil -> :no_node
      node -> run(node, ["-e", Enum.map_join(@corpus, "\n", &"console.log(String(#{lit(&1)}))")])
    end
  end

  defp beam_out do
    {:ok, m} = Rian.Beam.load(@src, :rian_show_float_conf)
    Enum.map(@corpus, &m.float(&1))
  end

  defp js_out do
    case System.find_executable("node") do
      nil ->
        :skip

      node ->
        # the module emits `export function float`; strip `export` to run as a script
        js = Rian.JS.compile(@src) |> String.replace("export function", "function")
        calls = Enum.map_join(@corpus, "\n", &"console.log(float(#{lit(&1)}));")
        run(node, ["-e", js <> "\n" <> calls])
    end
  end

  defp rust_out do
    case System.find_executable("rustc") do
      nil ->
        :skip

      rustc ->
        rust = Enum.map_join(Rian.Decl.compile(@src), "\n", fn {_, o} -> o[:rust] || "" end)
        body = Enum.map_join(@corpus, "\n", &"    println!(\"{}\", show::float(#{lit(&1)}f64));")
        dir = System.tmp_dir!()
        f = Path.join(dir, "rian_show_#{System.unique_integer([:positive])}.rs")
        bin = String.trim_trailing(f, ".rs")
        File.write!(f, rust <> "\nfn main() {\n" <> body <> "\n}\n")
        {_, 0} = System.cmd(rustc, ["-O", "--edition", "2021", "-A", "warnings", f, "-o", bin])
        out = run(bin, [])
        File.rm(f)
        File.rm(bin)
        out
    end
  end

  defp jvm_out do
    case {System.find_executable("kotlinc"), System.find_executable("java")} do
      {nil, _} ->
        :skip

      {_, nil} ->
        :skip

      {kotlinc, java} ->
        kt = Rian.JVM.compile(@src)
        body = Enum.map_join(@corpus, "\n", &"  println(float(#{lit(&1)}))")
        dir = System.tmp_dir!()
        f = Path.join(dir, "rian_show_#{System.unique_integer([:positive])}.kt")
        jar = String.replace_suffix(f, ".kt", ".jar")
        File.write!(f, kt <> "\n\nfun main() {\n" <> body <> "\n}\n")
        {_, 0} = System.cmd(kotlinc, [f, "-include-runtime", "-d", jar], stderr_to_stdout: true)
        out = run(java, ["-jar", jar])
        File.rm(f)
        File.rm(jar)
        out
    end
  end

  # an exact-round-trip literal for the double (valid in Rian/Elixir, JS and Rust)
  defp lit(x), do: :erlang.float_to_binary(x, [:short])

  defp run(cmd, args) do
    {out, 0} = System.cmd(cmd, args)
    out |> String.trim() |> String.split("\n")
  end

  test "Show.float equals ECMAScript String(x) on BEAM, Rust and JS (byte-identical)" do
    case reference() do
      :no_node ->
        # no node = no reference; still assert BEAM produced a value per input
        assert length(beam_out()) == length(@corpus)

      ref ->
        beam = beam_out()

        assert beam == ref,
               "BEAM Show.float diverges from ECMAScript String(x):\n" <> diff(ref, beam)

        for {target, outs} <- [js: js_out(), rust: rust_out()] do
          case outs do
            :skip -> :ok
            got -> assert got == ref, "#{target} Show.float diverges:\n" <> diff(ref, got)
          end
        end
    end
  end

  @tag :jvm
  test "Show.float equals ECMAScript String(x) on the JVM — the whole corpus, denormals included" do
    case System.find_executable("node") do
      nil ->
        :ok

      node ->
        {ref, 0} =
          System.cmd(node, [
            "-e",
            Enum.map_join(@corpus, "\n", &"console.log(String(#{lit(&1)}))")
          ])

        ref = ref |> String.trim() |> String.split("\n")

        case jvm_out() do
          :skip ->
            :ok

          got ->
            assert got == ref, "JVM Show.float diverges:\n" <> diff(ref, got)
        end
    end
  end

  defp diff(ref, got), do: diff(@corpus, ref, got)

  defp diff(corpus, ref, got) do
    Enum.zip([corpus, ref, got])
    |> Enum.reject(fn {_, r, g} -> r == g end)
    |> Enum.map_join("\n", fn {x, r, g} ->
      "  #{inspect(x)}: ecma=#{inspect(r)} got=#{inspect(g)}"
    end)
  end
end

defmodule Rian.InterpFloatConformanceTest do
  # async: false — loads a module into the VM via Rian.Beam.load.
  use ExUnit.Case, async: false

  # ADR-0069 Float64 unlock, step 1: the premise. `__prim_float_repr` emits each
  # target's NATIVE shortest-round-trip float string. Shortest-round-trip is
  # mathematically UNIQUE, so the *digits* must be identical across BEAM, Rust, JS
  # and the JVM — only the presentation (`1.0` vs `1`, exponent style) differs.
  # This test compiles the same function to every available target, runs it over a
  # corpus, normalizes each output to `(sign, digits, exp)`, and asserts they agree
  # — the foundation the portable ECMAScript formatter (`Rian.Show.float`) builds on.

  @src "def repr(x Float64) String := __prim_float_repr(x)"

  @corpus [1.0, 100.0, 0.1, 3.14, 2.5, 1.0e21, 1.0e-7, 123_456.789, 0.5, -2.5, 42.0, 0.0]

  # parse any of the targets' shortest forms ("1.0", "100.0", "0.1", "1.0e21",
  # "1.0E-7", "1e-7", "1.23456789e5", "-2.5") to a canonical {sign, digits, exp}
  # where value = sign · 0.<digits> · 10^exp, digits has no leading/trailing zeros.
  defp norm(str) do
    {sign, rest} =
      case str do
        "-" <> r -> {-1, r}
        r -> {1, r}
      end

    {mantissa, e} =
      case String.split(String.downcase(rest), "e") do
        [m] -> {m, 0}
        [m, exp] -> {m, String.to_integer(exp)}
      end

    {int_part, frac_part} =
      case String.split(mantissa, ".") do
        [i] -> {i, ""}
        [i, f] -> {i, f}
      end

    raw = int_part <> frac_part
    # exponent of the first digit: value = raw · 10^(e - len(frac_part))
    digits = String.trim_leading(raw, "0")
    lead_zeros = byte_size(raw) - byte_size(digits)
    point_exp = byte_size(int_part) + e - lead_zeros
    digits = String.trim_trailing(digits, "0")

    cond do
      digits == "" -> {0, "0", 0}
      true -> {sign, digits, point_exp}
    end
  end

  defp beam_outputs do
    {:ok, m} = Rian.Beam.load(@src, :rian_float_repr_conf)
    Enum.map(@corpus, &m.repr(&1))
  end

  defp js_outputs do
    case System.find_executable("node") do
      nil ->
        :no_node

      node ->
        js = Rian.JS.compile(@src)
        calls = Enum.map_join(@corpus, "\n", &"console.log(repr(#{float_lit(&1)}));")
        run(node, ["-e", js <> "\n" <> calls])
    end
  end

  defp rust_outputs do
    case System.find_executable("rustc") do
      nil ->
        :no_rustc

      rustc ->
        [{_, %{rust: rust}}] = Rian.Decl.compile(@src)
        body = Enum.map_join(@corpus, "\n", &"    println!(\"{}\", repr(#{float_lit(&1)}f64));")
        src = rust <> "\nfn main() {\n" <> body <> "\n}\n"
        dir = System.tmp_dir!()
        f = Path.join(dir, "rian_fconf_#{System.unique_integer([:positive])}.rs")
        bin = String.trim_trailing(f, ".rs")
        File.write!(f, src)
        {_, 0} = System.cmd(rustc, ["-O", "--edition", "2021", f, "-o", bin])
        out = run(bin, [])
        File.rm(f)
        File.rm(bin)
        out
    end
  end

  defp jvm_outputs do
    case {System.find_executable("kotlinc"), System.find_executable("java")} do
      {nil, _} ->
        :no_jvm

      {_, nil} ->
        :no_jvm

      {kotlinc, _} ->
        kt = Rian.JVM.compile(@src)
        body = Enum.map_join(@corpus, "\n", &"  println(repr(#{float_lit(&1)}))")
        base = Path.join(System.tmp_dir!(), "rian_fconf_#{System.unique_integer([:positive])}")
        src = base <> ".kt"
        jar = base <> ".jar"
        File.write!(src, kt <> "\n\nfun main() {\n" <> body <> "\n}\n")
        {_, 0} = System.cmd(kotlinc, [src, "-include-runtime", "-d", jar], stderr_to_stdout: true)
        out = run("java", ["-jar", jar])
        File.rm(src)
        File.rm(jar)
        out
    end
  end

  # a Rian/Elixir float literal that round-trips the double exactly
  defp float_lit(x), do: :erlang.float_to_binary(x, [:short])

  defp run(cmd, args) do
    {out, 0} = System.cmd(cmd, args)
    out |> String.trim() |> String.split("\n")
  end

  test "every target's shortest float repr carries identical digits (ADR-0069 premise)" do
    beam = Enum.map(beam_outputs(), &norm/1)

    for {target, outs} <- [js: js_outputs(), rust: rust_outputs(), jvm: jvm_outputs()] do
      case outs do
        skip when skip in [:no_node, :no_rustc, :no_jvm] ->
          :ok

        list ->
          got = Enum.map(list, &norm/1)

          assert got == beam,
                 "#{target} float digits diverge from BEAM:\n" <>
                   Enum.map_join(Enum.zip([@corpus, beam, got]), "\n", fn {x, b, g} ->
                     "  #{inspect(x)}: beam=#{inspect(b)} #{target}=#{inspect(g)}"
                   end)
      end
    end
  end
end

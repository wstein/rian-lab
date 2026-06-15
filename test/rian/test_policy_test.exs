defmodule Rian.TestPolicyTest do
  use ExUnit.Case, async: true

  # Guards the external-toolchain test policy (see `test/test_helper.exs`): the
  # slow `kotlinc`/`java`-dependent JVM tests are `@tag :jvm` so the default
  # `mix test` can exclude them, while the fast emitted-Kotlin *shape* assertions
  # stay in the inner loop. This guard fails the build if that tag ever drifts —
  # an untagged toolchain test would silently rejoin (and slow) the default loop;
  # an over-tagged shape test would silently drop coverage from it.
  @jvm_test "test/rian/jvm_test.exs"

  # A test depends on the JVM toolchain iff it either spawns it directly
  # (`to_jar`, `java`, probing for `kotlinc`) or consumes the batched-execution
  # results compiled in `setup_all` (`jvm_kt` / `expect_jvm`). Both must carry
  # `@tag :jvm`; a pure `JVM.compile` shape test must not.
  @toolchain ~r/System\.cmd\(java|to_jar\(|find_executable\("kotlinc"\)|jvm_kt\(|expect_jvm\(/

  test "every kotlinc/java-dependent JVM test is `@tag :jvm`, and no shape-only test is" do
    blocks = test_blocks(File.read!(@jvm_test))
    assert blocks != [], "found no `test` blocks in #{@jvm_test} — parser drifted?"

    mistagged =
      for %{name: name, tagged?: tagged?, toolchain?: toolchain?} <- blocks,
          tagged? != toolchain? do
        if toolchain?,
          do: "MISSING @tag :jvm (spawns the toolchain): #{name}",
          else: "STRAY @tag :jvm (shape-only, belongs in the fast loop): #{name}"
      end

    assert mistagged == [], "JVM test tagging drifted:\n" <> Enum.join(mistagged, "\n")
  end

  # Split the source into 4-space-indented `test "..."` … `end` blocks, recording
  # the test name, whether `@tag :jvm` precedes it, and whether it spawns the
  # toolchain. Mirrors the awk classifier used to apply the tags.
  defp test_blocks(src) do
    lines = String.split(src, "\n")

    {blocks, _} =
      Enum.reduce(lines, {[], %{tagged?: false}}, fn line, {acc, st} ->
        cond do
          String.trim(line) == "@tag :jvm" ->
            {acc, %{tagged?: true}}

          name = test_name(line) ->
            {[%{name: name, tagged?: st.tagged?, toolchain?: false, open?: true} | acc],
             %{tagged?: false}}

          line == "    end" ->
            {close_block(acc), st}

          true ->
            {accumulate(acc, line), st}
        end
      end)

    Enum.reverse(blocks)
  end

  # Matches the opening line of a 4-space-indented `test "name" …` block. Anchors
  # only on the name, not a trailing ` do`, so a wrapped multi-line signature
  # (`test "name", %{\n  jvm: jvm\n} do`) is still recognized.
  defp test_name(line) do
    case Regex.run(~r/^    test "(.*?)"/, line) do
      [_, name] -> name
      _ -> nil
    end
  end

  defp accumulate([%{open?: true} = b | rest], line),
    do: [%{b | toolchain?: b.toolchain? or Regex.match?(@toolchain, line)} | rest]

  defp accumulate(acc, _line), do: acc

  defp close_block([%{open?: true} = b | rest]), do: [%{b | open?: false} | rest]
  defp close_block(acc), do: acc
end

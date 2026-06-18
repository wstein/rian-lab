defmodule Mix.Tasks.Compile.RianTest do
  # async: false — loads compiled `.beam` into the shared VM.
  @moduledoc "The BEAM PULL plugin (ADR-0082 step 5): a Mix compiler for `.rian` sources."
  use ExUnit.Case, async: false

  alias Mix.Tasks.Compile.Rian

  # a tiny project dir with `src/<name>` files; returns the project root.
  defp project(files) do
    dir = Path.join(System.tmp_dir!(), "rian_pull_#{System.unique_integer([:positive])}")
    File.mkdir_p!(Path.join(dir, "src"))
    on_exit(fn -> File.rm_rf(dir) end)

    Enum.each(files, fn {name, content} -> File.write!(Path.join([dir, "src", name]), content) end)

    dir
  end

  test "compiles a flat .rian into a file-named module in dest — loadable + runnable" do
    dir = project([{"pull_probe.rian", "pub def answer() Int53 := 42\n"}])
    dest = Path.join(dir, "ebin")

    assert {:ok, []} = Rian.compile(["src"], dir, dest)
    assert File.exists?(Path.join(dest, "Elixir.PullProbe.beam"))

    :code.purge(:"Elixir.PullProbe")
    true = :code.add_path(String.to_charlist(dest))
    {:module, m} = :code.load_file(:"Elixir.PullProbe")
    assert m.answer() == 42
    on_exit(fn -> :code.purge(:"Elixir.PullProbe") && :code.delete(:"Elixir.PullProbe") end)
  end

  test "a file of `mod` declarations compiles to its module name" do
    dir = project([{"thing.rian", "mod PullMod do\n  pub def v() Int53 := 7\nend\n"}])
    dest = Path.join(dir, "ebin")

    assert {:ok, []} = Rian.compile(["src"], dir, dest)
    assert File.exists?(Path.join(dest, "Elixir.PullMod.beam"))
  end

  test "no .rian sources → :noop" do
    dir = project([])
    assert {:noop, []} = Rian.compile(["src"], dir, Path.join(dir, "ebin"))
  end

  test "a type error becomes an :error diagnostic, not a raise" do
    dir = project([{"bad.rian", "pub def f() Bool := 1 + 1\n"}])

    assert {:error, [diag]} = Rian.compile(["src"], dir, Path.join(dir, "ebin"))
    assert diag.severity == :error
    assert diag.compiler_name == "rian"
    assert diag.file =~ "bad.rian"
  end
end

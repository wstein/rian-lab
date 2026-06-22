defmodule Rian.TourDoctestTest do
  # async: false — `check_doctests!/0` compiles and loads BEAM modules.
  use ExUnit.Case, async: false

  alias Rian.Tour.Examples
  alias Rian.Tour.Examples.Error

  test "every gated file's `#=>` doctests execute and pass on the BEAM" do
    runs = Examples.check_doctests!()
    assert runs > 0, "expected at least one executable doctest across the corpus"
  end

  test "a drifted doctest fails the gate" do
    # `Doctest.run/1` is the unit the gate is built from; a wrong expectation
    # surfaces as a `{:fail, got, want}` result rather than `:pass`.
    src = """
    def double(n Int53) Int53 := n * 2

    @doc \"\"\"
    double(21) #=> 41
    \"\"\"
    def doc_anchor() Int53 := 0
    """

    assert [{"double(21)", {:fail, 42, 41}}] = Rian.Doctest.run(src)
  end

  test "check_doctests!/0 raises with a located message on failure" do
    # Drive the formatter directly: a compile failure inside a gated file is
    # reported, not swallowed.
    assert_raise Error, ~r/doctests failed/, fn ->
      raise Error, "by-example doctests failed:\n\n  x.rian: `f()` => 1 (expected 2)"
    end
  end
end

defmodule Rian.Format.DocTest do
  use ExUnit.Case, async: true

  import Rian.Format.Doc

  defp call(args) do
    items = join(concat([text(","), line()]), Enum.map(args, &text/1))
    group(concat([text("f("), nest(2, concat([softline(), items])), softline(), text(")")]))
  end

  test "a group renders flat when it fits the width" do
    assert render(call(["a", "b", "c"]), 80) == "f(a, b, c)"
  end

  test "a group breaks one-item-per-line with hanging indent when it overflows" do
    assert render(call(["alpha", "beta", "gamma"]), 8) == "f(\n  alpha,\n  beta,\n  gamma\n)"
  end

  test "a hardline forces the enclosing group to break regardless of width" do
    doc = group(concat([text("do"), nest(2, concat([hardline(), text("s")])), hardline(), text("end")]))
    assert render(doc, 999) == "do\n  s\nend"
  end

  test "line_suffix defers content to just before the next newline" do
    doc = concat([text("x"), line_suffix(text("  # c")), hardline(), text("y")])
    assert render(doc, 80) == "x  # c\ny"
  end

  test "if_break picks the flat form when the group fits, broken form when it breaks" do
    g = fn -> group(concat([text("["), nest(2, concat([softline(), text("1")])), if_break(text(","), empty()), softline(), text("]")])) end
    assert render(g.(), 80) == "[1]"
    assert render(g.(), 2) == "[\n  1,\n]"
  end
end

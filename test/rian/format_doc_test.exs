defmodule Rian.Format.DocTest do
  use ExUnit.Case, async: true

  @moduledoc """
  Direct unit tests for the Wadler/Lindig pretty-printing algebra
  (`Rian.Format.Doc`). The formatter exercises most paths end-to-end; these pin
  the algebra itself, including the constructor edge cases and the line-suffix
  flush path the formatter doesn't currently reach.
  """

  alias Rian.Format.Doc

  describe "constructors" do
    test "concat flattens empties, collapses singletons, and the 2-arity form delegates" do
      assert Doc.concat([Doc.empty(), Doc.empty()]) == :empty
      assert Doc.concat([Doc.text("a"), Doc.empty()]) == {:text, "a"}

      assert Doc.concat(Doc.text("a"), Doc.text("b")) ==
               Doc.concat([Doc.text("a"), Doc.text("b")])
    end

    test "join is empty for [] and intersperses otherwise" do
      assert Doc.join(Doc.text(", "), []) == :empty
      assert Doc.render(Doc.join(Doc.text(", "), [Doc.text("a"), Doc.text("b")]), 80) == "a, b"
    end

    test "group marks must-break when forced or when it contains a hardline" do
      assert {:group, true, _} = Doc.group(Doc.text("x"), true)
      assert {:group, false, _} = Doc.group(Doc.text("x"))
      assert {:group, true, _} = Doc.group(Doc.concat([Doc.text("x"), Doc.hardline()]))
    end
  end

  describe "render — flat vs broken" do
    defp list_doc do
      Doc.group(
        Doc.concat([
          Doc.text("["),
          Doc.nest(
            2,
            Doc.concat([Doc.softline(), Doc.text("a"), Doc.text(","), Doc.line(), Doc.text("b")])
          ),
          Doc.softline(),
          Doc.text("]")
        ])
      )
    end

    test "a group that fits renders flat (line→space, softline→\"\")" do
      assert Doc.render(list_doc(), 80) == "[a, b]"
    end

    test "a group that exceeds the width breaks (newline + nest indent)" do
      assert Doc.render(list_doc(), 4) == "[\n  a,\n  b\n]"
    end

    test "a hardline forces a break even when the content would fit" do
      assert Doc.render(Doc.group(Doc.concat([Doc.text("a"), Doc.hardline(), Doc.text("b")])), 80) ==
               "a\nb"
    end

    test "if_break picks flat vs broken with its enclosing group" do
      flat = Doc.group(Doc.concat([Doc.text("x"), Doc.if_break(Doc.text(","), Doc.text(";"))]))
      assert Doc.render(flat, 80) == "x;"

      broken =
        Doc.group(
          Doc.concat([Doc.text("x"), Doc.if_break(Doc.text(","), Doc.text(";")), Doc.hardline()])
        )

      assert Doc.render(broken, 80) == "x,\n"
    end

    test "fits? measures a following must-break group as broken (bounded lookahead)" do
      # the second group must break; the first is fits-checked with it in `rest`.
      doc = Doc.concat([Doc.group(Doc.text("a")), Doc.group(Doc.hardline())])
      assert Doc.render(doc, 80) == "a\n"
    end
  end

  describe "line_suffix — deferred-to-newline content" do
    test "suffix is emitted just before the next newline" do
      doc =
        Doc.concat([
          Doc.text("code"),
          Doc.line_suffix(Doc.text("  # c")),
          Doc.hardline(),
          Doc.text("next")
        ])

      assert Doc.render(doc, 80) == "code  # c\nnext"
    end

    test "a suffix still pending at end-of-document is flushed (every flat_string shape)" do
      rich =
        Doc.line_suffix(
          Doc.concat([
            Doc.empty(),
            Doc.text("[t]"),
            Doc.nest(2, Doc.text("[n]")),
            Doc.group(Doc.text("[g]")),
            Doc.line(),
            Doc.hardline(),
            Doc.line_suffix(Doc.text("[ls]")),
            Doc.if_break(Doc.text("[b]"), Doc.text("[f]"))
          ])
        )

      assert Doc.render(Doc.concat([Doc.text("x"), rich]), 80) == "x[t][n][g] [ls][f]"
    end

    test "a bare empty suffix flushes to nothing (concat would otherwise strip it)" do
      assert Doc.render(Doc.concat([Doc.text("x"), Doc.line_suffix(Doc.empty())]), 80) == "x"
    end
  end
end

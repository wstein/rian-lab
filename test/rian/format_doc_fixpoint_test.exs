defmodule Rian.FormatDocFixpointTest do
  # async: false — loads a real module into the VM via :code.load_binary.
  use ExUnit.Case, async: false

  alias Rian.Beam
  alias Rian.Format.Doc

  # Self-hosting fixpoint for the formatter's pretty-printing **engine** (ADR-0045):
  # a Rian port of `Rian.Format.Doc` (compiler/format.rian), compiled to real `.beam`,
  # its `render/2` **diffed against the reference `Rian.Format.Doc.render/2`**. Both
  # engines build the *same* document from a shared recipe (via each side's
  # constructors, so break-propagation is each engine's own) and must render
  # byte-identical output across a range of widths — turning the ported engine into a
  # regression test, not a demo.

  setup_all do
    {:ok, mod} = Beam.load(File.read!("compiler/format.rian"), :rian_format_doc_fixpoint)
    {:ok, mod: mod}
  end

  # A "builder" is a map of constructor closures, so one recipe drives both engines.
  defp rian_b(mod) do
    %{
      empty: &mod.dempty/0,
      text: &mod.dtext/1,
      concat: &mod.dconcat/1,
      nest: &mod.dnest/2,
      line: &mod.dline/0,
      soft: &mod.dsoft/0,
      hard: &mod.dhard/0,
      group: &mod.dgroup/1,
      group_f: &mod.dgroup_forced/1,
      suffix: &mod.dsuffix/1,
      if_break: &mod.dif_break/2,
      render: &mod.render/2
    }
  end

  defp ex_b do
    %{
      empty: fn -> Doc.empty() end,
      text: &Doc.text/1,
      concat: &Doc.concat/1,
      nest: &Doc.nest/2,
      line: &Doc.line/0,
      soft: &Doc.softline/0,
      hard: &Doc.hardline/0,
      group: &Doc.group/1,
      group_f: &Doc.group(&1, true),
      suffix: &Doc.line_suffix/1,
      if_break: &Doc.if_break/2,
      render: &Doc.render/2
    }
  end

  # ── recipes (one shape per clause; `b` is the builder) ────────────────────
  defp recipe("plain text", b), do: b.text.("hello world")
  defp recipe("concat + nest", b), do: b.concat.([b.text.("a"), b.nest.(2, b.text.("b"))])
  defp recipe("call group", b), do: call(b, ["alpha", "beta", "gamma"])
  defp recipe("single-arg call", b), do: call(b, ["x"])
  defp recipe("empty group", b), do: b.group.(b.concat.([b.text.("("), b.text.(")")]))

  defp recipe("nested calls", b) do
    b.group.(
      b.concat.([
        b.text.("outer("),
        b.nest.(
          2,
          b.concat.([b.soft.(), call(b, ["aa", "bb"]), b.text.(","), b.line.(), call(b, ["cc", "dd"])])
        ),
        b.soft.(),
        b.text.(")")
      ])
    )
  end

  defp recipe("hardline forces break", b) do
    b.group.(
      b.concat.([
        b.text.("do"),
        b.nest.(2, b.concat.([b.hard.(), b.text.("s")])),
        b.hard.(),
        b.text.("end")
      ])
    )
  end

  defp recipe("line_suffix comment", b) do
    b.concat.([b.text.("x"), b.suffix.(b.text.("  # c")), b.hard.(), b.text.("y")])
  end

  defp recipe("forced group (magic comma)", b), do: b.group_f.(call_inner(b, ["p", "q"]))

  defp recipe("if_break only", b) do
    b.group.(
      b.concat.([
        b.text.("["),
        b.nest.(2, b.concat.([b.soft.(), b.text.("1")])),
        b.if_break.(b.text.(","), b.empty.()),
        b.soft.(),
        b.text.("]")
      ])
    )
  end

  @recipe_names [
    "plain text",
    "concat + nest",
    "call group",
    "single-arg call",
    "empty group",
    "nested calls",
    "hardline forces break",
    "line_suffix comment",
    "forced group (magic comma)",
    "if_break only"
  ]

  # comma+line separated items wrapped in a 2-space nested group: `f(a, b, c)`
  defp call(b, args), do: b.group.(call_inner_named(b, "f(", args))
  defp call_inner(b, args), do: call_inner_named(b, "g(", args)

  defp call_inner_named(b, open, args) do
    items =
      args
      |> Enum.map(&b.text.(&1))
      |> Enum.intersperse(b.concat.([b.text.(","), b.line.()]))
      |> b.concat.()

    b.concat.([
      b.text.(open),
      b.nest.(2, b.concat.([b.soft.(), items])),
      b.if_break.(b.text.(","), b.empty.()),
      b.soft.(),
      b.text.(")")
    ])
  end

  @widths [2, 4, 8, 16, 40, 80]

  for name <- @recipe_names do
    @name name
    test "the ported engine renders #{name} identically to Rian.Format.Doc", %{mod: mod} do
      rian_doc = recipe(@name, rian_b(mod))
      ex_doc = recipe(@name, ex_b())

      for w <- @widths do
        assert mod.render(rian_doc, w) == Doc.render(ex_doc, w),
               "diverged on #{@name} at width #{w}"
      end
    end
  end
end

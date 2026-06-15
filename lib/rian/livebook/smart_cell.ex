# Conditionally compiled: the module exists only where `Kino.SmartCell` is loaded
# (a Livebook runtime, or this project's own dev/test where Kino is an optional
# dep). A plain consumer of the compiler library that never loads Kino simply does
# not get this module — `Rian.Application` guards its registration the same way.
if Code.ensure_loaded?(Kino.SmartCell) do
  defmodule Rian.Livebook.SmartCell do
    @moduledoc """
    A Livebook **Rian** smart cell (ADR-0053): a code editor whose contents are
    evaluated by `Rian.Livebook.eval/1` against the notebook's shared session, so
    `def`/`type`/`:=` made in one Rian cell carry into the next.

    The cell uses Livebook's built-in collaborative editor for the Rian source and
    persists exactly one attribute — `"source"`. Its generated code is the plain,
    readable `Rian.Livebook.eval("…")`, so the cell never hides what it runs.
    """
    use Kino.JS
    use Kino.JS.Live
    use Kino.SmartCell, name: "Rian"

    @impl true
    def init(attrs, ctx) do
      source = attrs["source"] || ""
      {:ok, assign(ctx, source: source), editor: [source: source, placement: :top]}
    end

    @impl true
    def handle_connect(ctx) do
      {:ok, %{}, ctx}
    end

    @impl true
    def handle_editor_change(source, ctx) do
      {:ok, assign(ctx, source: source)}
    end

    @impl true
    def to_attrs(ctx) do
      %{"source" => ctx.assigns.source}
    end

    @impl true
    def to_source(attrs) do
      quote do
        Rian.Livebook.eval(unquote(attrs["source"]))
      end
      |> Kino.SmartCell.quoted_to_string()
    end

    asset "main.js" do
      """
      export function init(ctx, payload) {
        ctx.root.innerHTML = `
          <div style="color: var(--gray-500, #61758a); font: 500 0.75rem/1 system-ui, sans-serif; padding: 4px 2px;">
            Rian — evaluated against the notebook's shared session
          </div>
        `;
      }
      """
    end
  end
end

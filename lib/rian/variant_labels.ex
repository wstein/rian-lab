defmodule Rian.VariantLabels do
  @moduledoc """
  Shared sum-variant **field-label** resolution (ADR-0049 §3b / ADR-0050).

  A sum variant may declare named fields (`Circle(radius Float64)`); a backend whose
  representation has named slots (a JS object `{ $: "Circle", radius }`, a Kotlin
  `data class Circle(val radius: …)`) wants those names at the construction *and*
  pattern sites. The names live on the `type` declaration's variant fields, but the
  pattern site (`Core.PCtor`) is reached deep inside the emitter where the type
  registry isn't threaded — so this module pre-resolves them onto the node:

  - `meta/1` builds the `ctor => %{enum, ctor, named, labels}` map from a program (the
    `labels` are the per-field names, `nil` for an anonymous field);
  - `bake_pats/2` is a reflective `Core`-tree walk that copies each `PCtor`'s `labels`
    off that map, so a downstream `pat_match` reads names off the node.

  `Rian.JS` additionally rewrites *construction* to an `EVariant` (its own pass, since
  the object form is JS-specific); `Rian.JVM` reads `meta/1` directly at the
  `data class` declaration and uses `bake_pats/2` for patterns. The BEAM emitter keeps
  positional tagged tuples (no named slot), so it does not consume this module.
  """

  use Rian.Ann

  alias Rian.Core.PCtor

  @typedoc "ctor name => its resolved field-label info"
  @type t :: %{
          optional(String.t()) => %{
            enum: String.t(),
            ctor: String.t(),
            named: boolean(),
            labels: [String.t() | nil]
          }
        }

  @doc """
  The `ctor => %{enum, ctor, named, labels}` map for every variant in `prog`
  (top-level `types` and module-nested `mods`). `named` is true when the variant has
  fields and *every* field is labeled.
  """
  @rian_sig "pub def meta(prog Prog) Dict(String, Any)"
  @spec meta(map()) :: t()
  def meta(prog) do
    types = Map.get(prog, :types, []) ++ for(m <- Map.get(prog, :mods, []), t <- m.types, do: t)

    for t <- types, v <- t.variants, into: %{} do
      labels = Enum.map(v.fields, &Map.get(&1, :label))
      named = v.fields != [] and Enum.all?(labels, & &1)
      {v.ctor, %{enum: t.name, ctor: v.ctor, named: named, labels: labels}}
    end
  end

  @doc """
  Reflectively walk a `Core` node (or any nested list/tuple/struct of them) and set each
  `PCtor`'s `labels` from `meta` — leaving a ctor not in `meta` (a non-variant pattern)
  untouched. Construction nodes are unaffected; this resolves the *pattern* side only.
  """
  @rian_sig "pub def bake_pats(node Any, meta Dict(String, Any)) Any"
  @spec bake_pats(term(), t()) :: term()
  def bake_pats(%PCtor{ctor: c, args: args} = n, meta) do
    labels = if info = Map.get(meta, c), do: info.labels, else: n.labels
    %PCtor{n | labels: labels, args: Enum.map(args, &bake_pats(&1, meta))}
  end

  def bake_pats(%_struct{} = n, meta) do
    struct(
      n.__struct__,
      n |> Map.from_struct() |> Map.new(fn {k, v} -> {k, bake_pats(v, meta)} end)
    )
  end

  def bake_pats(l, meta) when is_list(l), do: Enum.map(l, &bake_pats(&1, meta))

  def bake_pats(t, meta) when is_tuple(t),
    do: t |> Tuple.to_list() |> Enum.map(&bake_pats(&1, meta)) |> List.to_tuple()

  def bake_pats(x, _meta), do: x
end

defmodule Rian.Core do
  @moduledoc """
  The **typed core IR** (ADR-0050) — the single representation that the checker
  and *all* emitters are migrating onto, replacing the loose surface tuples the
  parser produces. Sealed-sum / typed-struct nodes (not tuples) mean one node
  shape, `@enforce_keys`-guaranteed, changed in one place — and, once the
  compiler is self-hosted, exhaustiveness over its *own* IR (ADR-0050 §4).

  Each node carries an optional `type` (the inferred type, ADR-0050 §3 / ADR-0034)
  the emitter reads off for representation choices (ADR-0041/0043/0046); it is
  `nil` until the checker fills it.

  ## Migration status

  This is the **first increment**: the **pattern** node catalogue plus
  `from_pat/1` (surface tuple → core), consumed by the abstract-forms emitter
  ([`Rian.Beam`](beam.ex)). Remaining, pass-by-pass behind tests (ADR-0050 §5):
  the expression catalogue, then the other emitters (`Rian.Lower` Elixir/Rust)
  and the exhaustiveness normalizer onto the core.
  """

  defmodule PWild do
    @moduledoc "`_` — matches anything."
    defstruct type: nil
  end

  defmodule PVar do
    @moduledoc "A variable binding pattern."
    @enforce_keys [:name]
    defstruct [:name, type: nil]
  end

  defmodule PLit do
    @moduledoc "A literal pattern (integer or string)."
    @enforce_keys [:value]
    defstruct [:value, type: nil]
  end

  defmodule PAtom do
    @moduledoc "An atom pattern (`:ok`)."
    @enforce_keys [:name]
    defstruct [:name, type: nil]
  end

  defmodule PTuple do
    @moduledoc "A tuple pattern `{p1, …}`."
    defstruct elems: [], type: nil
  end

  defmodule PList do
    @moduledoc "A list pattern; `tail` is `:close` (`[a, b]`) or a pattern (`[a | t]`)."
    defstruct elems: [], tail: :close, type: nil
  end

  defmodule PCtor do
    @moduledoc "A sum-variant pattern `Ctor(args…)` (nullary when `args == []`)."
    @enforce_keys [:ctor]
    defstruct ctor: nil, args: [], type: nil
  end

  @doc "Translate a surface pattern (the `Rian.Pratt` tuple AST) into the typed core."
  def from_pat(:wild), do: %PWild{}
  def from_pat({:var, name}), do: %PVar{name: name}
  def from_pat({:lit, value}), do: %PLit{value: value}
  def from_pat({:atom, name}), do: %PAtom{name: name}
  def from_pat({:tuple, ps}), do: %PTuple{elems: Enum.map(ps, &from_pat/1)}
  def from_pat({:ctor, ctor, args}), do: %PCtor{ctor: ctor, args: Enum.map(args, &from_pat/1)}
  def from_pat({:list, ps, :close}), do: %PList{elems: Enum.map(ps, &from_pat/1), tail: :close}

  def from_pat({:list, ps, {:tail, t}}),
    do: %PList{elems: Enum.map(ps, &from_pat/1), tail: from_pat(t)}
end

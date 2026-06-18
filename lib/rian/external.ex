defmodule Rian.External do
  @moduledoc """
  Lowering for `@external` FFI specs (ADR-0068) — the neutral home shared by every
  emitter (`Rian.Beam`/`Rian.JS`/`Rian.JVM`/`Rian.Lower`), so the backends don't
  reach into `Rian.Decl` (the parser) for a rendering helper. `Rian.Decl` *parses*
  an `@external` spec to a string or a `{:ref, parts, erlang?}` reference; this module
  *renders* it to a host-call expression. (The ADR-0080 §7 foreign-file lowering, when
  it lands, also belongs here.)
  """

  @typedoc """
  An `@external` spec (ADR-0068): a raw host-expression string, or a parsed function
  reference `{:ref, name_parts, erlang?}` (`:erlang.fun` → `erlang? = true`).
  """
  @type spec :: String.t() | {:ref, [String.t()], boolean()}

  @doc """
  Render an `@external` spec to a host-call string for an emitter (ADR-0068): a raw
  string passes through; a reference `{:ref, parts, erlang?}` becomes a positional call
  `path(p1, p2, …)` over the function's params. So a reference lowers via the existing
  string-splicing path in every emitter — one helper, no per-backend reference logic.

  **Calling convention (the author's contract):** the referenced function must take the
  **same parameters in the same order** as the Rian `def` — the args are passed
  **positionally**. `Rian.Check`'s resolution verifies the *arity* matches, but **not**
  the order/types; a target that reorders or retypes its params will match arity yet be
  miswired silently. (Same trust boundary as any FFI — ADR-0068: this is FFI, not magic.)
  """
  @spec render(spec(), [map()]) :: String.t()
  def render(spec, _params) when is_binary(spec), do: spec

  def render({:ref, parts, erlang?}, params) do
    path = if erlang?, do: ":" <> Enum.join(parts, "."), else: Enum.join(parts, ".")
    "#{path}(#{Enum.map_join(params, ", ", & &1.name)})"
  end
end

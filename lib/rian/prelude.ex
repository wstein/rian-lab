defmodule Rian.Prelude do
  @moduledoc """
  The portable prelude (ADR-0047 tier 1 / ADR-0041 module-resolution kind 3):
  types auto-available in every module on every target, with no user declaration.

  This increment provides the flagship decision — **`Option(T) = Some(T) | None`,
  no `nil`** (ADR-0047 §3). `Option` is a sealed sum like any other (so `case`
  over it is exhaustiveness-checkable, ADR-0034), but it is *built in*: the
  checker, exhaustiveness env, and lowering meta all know `Some`/`None` without a
  `type Option := …` in the source, and the type's definition is **not emitted**
  — it lowers to a tagged tuple / atom on the BEAM (`{:some, v}` / `:none`) and to
  the native `Option` on Rust (`Option::Some(v)` / `Option::None`).

  The broader stdlib (`List`/`Map`/`String` operations, written in Rian over a
  per-target primitive layer, ADR-0047 §2) awaits the collection-representation
  work; this fixes the prelude *mechanism* and its first member.
  """
  alias Rian.IR.{Field, Type, Variant}

  @doc "The built-in prelude types (known everywhere, never re-emitted as user types)."
  def types do
    [
      %Type{
        name: "Option",
        variants: [
          %Variant{ctor: "Some", fields: [%Field{type: "T"}]},
          %Variant{ctor: "None", fields: []}
        ]
      }
    ]
  end

  @doc "Prepend the prelude types to a program's user types (for env/meta/inference)."
  def with_prelude(types), do: types() ++ types
end

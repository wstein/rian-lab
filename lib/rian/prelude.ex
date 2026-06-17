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

  It also **links the portable-prelude functions** (`List`/`Dict`/`Str`/`Int`,
  written in Rian over a per-target primitive layer, ADR-0047 §2): the sources are
  bundled into this module at compile time, compile to private `Rian.Prelude.<Name>`
  BEAM modules (so they never clobber Elixir's `List` etc.), and `Rian.Beam`
  redirects a `List.fun(…)` call to its linked module when the prelude defines that
  function (an unimplemented one still falls through to Elixir as FFI). `Rian.Reach`
  treats such a call as portable, so it reaches all four targets.
  """
  alias Rian.IR.{Field, Type, Variant}

  @doc "The built-in prelude types (known everywhere, never re-emitted as user types)."
  @spec types() :: [struct()]
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
  @spec with_prelude([struct()]) :: [struct()]
  def with_prelude(types), do: types() ++ types

  # ── portable-prelude FUNCTION linkage (ADR-0047 §2) ──────────────────────────
  #
  # `List`/`Dict`/`Str`/`Int` are written in Rian (`examples/rian/prelude_*.rian`).
  # A program that calls them must have them *present* to compile and run, but they
  # cannot load under `Elixir.List` etc. (that would clobber Elixir's own stdlib),
  # so each links under a private `Rian.Prelude.<Name>` atom; `Rian.Beam` redirects
  # `List.fun(…)` calls to it (`module_atom/1`). The sources are bundled into this
  # `.beam` at compile time so the linked modules need no source tree at runtime.

  @prelude_names ~w(List Dict Str Int)

  for n <- ~w(list dict str int), do: @external_resource("examples/rian/prelude_#{n}.rian")

  @prelude_sources for n <- ~w(list dict str int),
                       do: File.read!("examples/rian/prelude_#{n}.rian")

  # The `{module, fun}` pairs the prelude actually defines — so only these redirect
  # to the linked module; an unimplemented `List.to_string` still hits Elixir's List.
  @prelude_exports for src <- @prelude_sources,
                       m <- Rian.Decl.parse(src).mods,
                       f <- m.funcs,
                       into: MapSet.new(),
                       do: {m.name, to_string(f.name)}

  @doc "The portable-prelude module names redirected to their linked `Rian.Prelude.*` atoms."
  @spec module_names() :: [String.t()]
  def module_names, do: @prelude_names

  @doc "Whether the portable prelude defines `Mod.fun` (only these calls redirect/are portable)."
  @spec defines?(String.t(), String.t()) :: boolean()
  def defines?(mod, fun), do: MapSet.member?(@prelude_exports, {mod, fun})

  @doc "The linked BEAM atom a prelude module call resolves to (`List` → `Rian.Prelude.List`)."
  @spec atom(String.t()) :: module()
  def atom(name), do: :"Elixir.Rian.Prelude.#{name}"

  @doc "Compile the bundled prelude sources to `[{linked_atom, beam_binary}]`."
  @spec beams() :: [{module(), binary()}]
  def beams do
    Enum.flat_map(@prelude_sources, fn src ->
      prog = Rian.Decl.parse(src)
      renamed = %{prog | mods: Enum.map(prog.mods, &%{&1 | name: "Rian.Prelude.#{&1.name}"})}
      Rian.Beam.compile_program_ir(renamed)
    end)
  end

  @doc "Load the linked prelude modules into the VM (idempotent), so calls to them run."
  @spec load() :: :ok
  def load do
    unless :code.is_loaded(atom("List")) != false do
      for {atom, bin} <- beams(),
          do: {:module, _} = :code.load_binary(atom, ~c"#{atom}.beam", bin)
    end

    :ok
  end
end

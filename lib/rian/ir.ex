defmodule Rian.IR do
  @moduledoc """
  The core intermediate representation — the typed structs the declaration
  parser (`Rian.Decl`) emits and the lowering backend (`Rian.Lower`) consumes.

  > **ADR-0050 (migrated).** The old "expr/pattern stay tuples as the IR" stance was overturned
  > (evidence: the B1 triplication in `SELFHOST.md`, three incoming emitters in ADR-0049). The
  > typed sealed-sum core IR is now `Rian.Core`, and **all four emitters (`Beam`/`Lower`/`JS`/`JVM`)
  > consume it** — each builds its Core via `Rian.Check.annotate/3`, so every node carries its
  > inferred `type` (§3 infrastructure). The expr/pattern tuples below are now the **transient
  > surface AST** that `Rian.Pratt` produces and `Rian.Core.from_expr`/`from_pat` immediately lower
  > into Core; no downstream pass walks them. (§3's remaining step: have the representation choices
  > in ADR-0041/0043/0046 *read* `node.type` instead of re-deriving it.)

  Declaration-level nodes are structs (below). The **surface** expression and
  pattern shapes that `Rian.Pratt` produces — lowered into `Rian.Core` before any
  emitter or the checker sees them — are:

      # Surface Expr (Rian.Pratt output → Core.from_expr)
      {:num, "42"} · {:str, s} · {:id, x} · {:atom, a} · {:bin, op, l, r}
      {:unary, op, x} · {:call, f, args} · {:dot, head, name} · {:lambda, ps, body}
      {:if, c, t, e} · {:case, scrut, arms} · {:block, stmts}
      {:list_lit, elems, tail} · {:map_lit, pairs} · {:capture, _} · {:cap_arg, _}

      # Surface Pattern (clause heads & case arms → Core.from_pat)
      :wild · {:var, name} · {:lit, value} · {:ctor, name, [pattern]} · {:tuple, [pattern]}
  """

  use Rian.Ann

  # ── the IR type vocabulary, authored as native Rian (ADR-0050 typed core, matching
  # the self-host's ported form). A capability is a small sum; a type-name field is a
  # `String`; a nullable field (Elixir default `nil`) is `Option(_)`; `Pat`/`Core` are
  # the Core sums defined centrally in core.rian — referenced by name, not redeclared.
  @rian_sig "type Cap := Val | Iso | Ref | Tag"

  @rian_sig "struct Field(label Option(String), type String)"
  @rian_sig "struct Variant(ctor String, fields Vec(Field))"
  @rian_sig "struct Type(name String, variants Vec(Variant), is_pub Bool, doc Option(String))"
  @rian_sig "struct Range(name String, base String, lo Int53, hi Int53, is_pub Bool, doc Option(String))"
  @rian_sig "struct Opaque(name String, base String, is_pub Bool, doc Option(String), ops Vec(String), casts Vec(String))"
  @rian_sig "struct Struct(name String, fields Vec(Field), is_pub Bool, doc Option(String))"
  @rian_sig "struct Const(name String, type String, value String, is_pub Bool, doc Option(String))"
  @rian_sig "struct Use(path String, names Vec(String))"
  @rian_sig "struct Param(name String, type String, cap Cap)"
  @rian_sig "struct Clause(pats Vec(Pat), body Core, guard Option(Core))"

  # The whole-program IR — the map `Rian.Decl.parse/1` returns and every gate/emitter
  # consumes (ADR-0050). The declaration buckets are cleanly typed IR records; the
  # protocol-machinery fields (`impls` = `(String, String)` pairs, `protocols`/
  # `impl_decls` = untyped tables) stay `_Unk` honestly until that layer is modelled.
  @rian_sig """
  type Prog := Prog(funcs Vec(Func), types Vec(Type), structs Vec(Struct),
                    opaques Vec(Opaque), ranges Vec(Range), mods Vec(Mod),
                    impls _Unk, protocols _Unk, impl_decls _Unk)
  """

  @rian_sig """
  struct Mod(name String, uses Vec(Use), types Vec(Type), ranges Vec(Range),
             opaques Vec(Opaque), structs Vec(Struct), consts Vec(Const),
             funcs Vec(Func), doc Option(String), targets Option(Vec(Symbol)))
  """

  @rian_sig """
  struct Func(name String, params Vec(Param), ret String, clauses Vec(Clause),
              is_pub Bool, tvars Vec(String), bounds Map(String, Vec(String)),
              doc Option(String), synthetic Bool, is_test Bool,
              dispatch Option(Symbol), externals Map(Symbol, String),
              effects Vec(Symbol), partial Bool)
  """

  defmodule Field do
    @moduledoc "A variant/struct field: an optional compile-time `label` and a `type`."
    @enforce_keys [:type]
    defstruct [:label, :type]

    @type t :: %__MODULE__{}
  end

  defmodule Variant do
    @moduledoc "A sum-type variant: a constructor name and its (ordered) fields."
    @enforce_keys [:ctor]
    defstruct ctor: nil, fields: []

    @type t :: %__MODULE__{}
  end

  defmodule Type do
    @moduledoc "A sum-type declaration (`type Name := …`). `pub?` marks it exported from a `mod`."
    @enforce_keys [:name]
    defstruct name: nil, variants: [], pub?: false, doc: nil

    @type t :: %__MODULE__{}
  end

  defmodule Range do
    @moduledoc """
    A finite ordinal subrange type (`range Name := lo..hi`, ADR-0036) over an
    ordinal base (`Int64` / `Char`). `lo`/`hi` are inclusive integer bounds (a
    `Char` bound is its codepoint). It registers a **finite** exhaustiveness
    signature (its member literals), and its name substitutes to `base` in every
    type position — the value *is* the base ordinal (representation, not newtype).
    """
    @enforce_keys [:name, :base, :lo, :hi]
    defstruct name: nil, base: nil, lo: nil, hi: nil, pub?: false, doc: nil

    @type t :: %__MODULE__{}
  end

  defmodule Opaque do
    @moduledoc """
    An **abstract type** (`opaque T := Base`, ADR-0067 / ADR-0043): a type that is
    nominally **distinct** from `Base` to the checker but **erases to `Base` at
    runtime on every target** (zero-cost — no wrapper, no box). Constructed by the
    total `T.of(x)` (x : Base); the abstraction lives only in `Rian.Check`, and
    `Rian.Opaque.erase/1` substitutes `T -> Base` and rewrites `T.of(x) -> x` before
    any emitter sees it.

    `ops` are declared operator rules (ADR-0067 P1b, `abstract … do op +(…) end`) —
    a set of operator strings the abstract overloads (each forwards to the base
    operator on the underlying representation). `casts` are declared `to base()`
    exposures (P1c). A plain `opaque` has empty `ops`/`casts`.
    """
    @enforce_keys [:name, :base]
    defstruct name: nil, base: nil, pub?: false, doc: nil, ops: [], casts: []

    @type t :: %__MODULE__{}
  end

  defmodule Struct do
    @moduledoc """
    A product-type declaration (`struct Name(field Type, …)`). Unlike a `Type`,
    which lowers to tagged tuples / a Rust `enum`, a `Struct` lowers to a named
    record on each target (`defstruct` on the BEAM, a `struct {…}` on Rust) and is
    built with constructor-call syntax (`Name(v1, v2)`).
    """
    @enforce_keys [:name]
    defstruct name: nil, fields: [], pub?: false, doc: nil

    @type t :: %__MODULE__{}
  end

  defmodule Const do
    @moduledoc """
    A named compile-time constant (`const NAME Type := value`). `value` is the
    body source (parsed on lowering, like a function body). Lowers to a 0-arity
    accessor on the BEAM (`def`/`defp`) and a `const` on Rust; `pub?` exports it.
    """
    @enforce_keys [:name, :type, :value]
    defstruct name: nil, type: nil, value: nil, pub?: false, doc: nil

    @type t :: %__MODULE__{}
  end

  defmodule Use do
    @moduledoc """
    An import inside a module. `use Path` is **qualified** (`names: []`) — it
    brings the module into scope, references stay qualified (`Math.pi`). `use
    Path.(a, b)` is **selective** — the listed `names` are usable unqualified.
    Lowers to `alias`/`import` (BEAM) and `use …;`/`use …::{…};` (Rust).
    """
    @enforce_keys [:path]
    defstruct path: nil, names: []

    @type t :: %__MODULE__{}
  end

  defmodule Mod do
    @moduledoc """
    A module (`mod Name do … end`) — a namespace grouping `uses`, `types`,
    `structs`, `consts`, and `funcs`. Lowers to a `defmodule` on the BEAM and a
    `mod` on Rust; `pub?` items are exported (`def`/`pub fn`), the rest private.

    `targets` is the `@targets(…)` contract (ADR-0058 §2): a list of required
    target environments (`:ex`/`:rs`/`:js`) every `pub` function must reach, or
    `nil` for no contract (no gate — constraints are selected by need).
    """
    @enforce_keys [:name]
    defstruct name: nil,
              uses: [],
              types: [],
              ranges: [],
              opaques: [],
              structs: [],
              consts: [],
              funcs: [],
              doc: nil,
              targets: nil

    @type t :: %__MODULE__{}
  end

  defmodule Param do
    @moduledoc "A function parameter: `name`, `type`, reference `cap`ability."
    @enforce_keys [:name, :type]
    defstruct name: nil, type: nil, cap: :val

    @type t :: %__MODULE__{}
  end

  defmodule Clause do
    @moduledoc "One function clause: argument `pats`, a `body` (source string — or the expanded `{:block, …}` AST after macro expansion, `Rian.Decl`), an optional `guard` (source string)."
    @enforce_keys [:pats, :body]
    defstruct pats: [], body: nil, guard: nil

    @type t :: %__MODULE__{}
  end

  defmodule Func do
    @moduledoc """
    A function: `name`, `params`, return type `ret`, `clauses`. `pub?` marks it
    exported from a `mod`. `tvars` are the `forall` type-variable names (ADR-0042),
    empty for a non-generic function; `bounds` maps a `tvar` to its protocol
    bounds (`forall T: Eq + Ord` -> `%{"T" => ["Eq", "Ord"]}`, ADR-0042 §2).
    `synthetic` marks a compiler-generated
    function — currently the `protocol` dispatcher (ADR-0042 §3/§6), which is
    **exempt from the exhaustiveness gate**: protocol dispatch is open by design
    (no case-arms, no totality requirement), unlike a user `case`. `test?` marks
    a `@test def` (ADR-0057) — a zero-arity `Bool` function the test runner
    (`Rian.Test`) executes and bridges to the host's xUnit framework.

    `dispatch` marks a function generated by the `protocol` desugaring (ADR-0061
    §1): `:dispatcher` is the guarded runtime dispatcher, `:impl` is a mangled
    `impl_*` method. The BEAM backend emits both. **JS** keeps the `:impl` methods
    (they lower as plain functions) but skips the `:dispatcher` and regenerates it
    with JS-native guards. **Rust** skips both and emits `trait`s + `impl`s from
    the protocol IR (`prog.protocols`/`prog.impl_decls`).

    `externals` is the `@external` target-scoped FFI bodies (ADR-0068): a map
    `%{target => "host expression"}`. A function with a non-empty `externals` has no
    portable Rian body (`clauses: []`) — its reach is exactly the declared targets
    (`Rian.Reach`), and each emitter lowers its own target's spec.

    `effects` is the declared `@effects(...)` set (ADR-0048/0081): a list of effect
    atoms (`[:host]`, …). `Rian.Check` verifies it equals the inferred set exactly
    (`Rian.Reach.effect_sets/1`); `[]` means undeclared (inferred, not forced).

    `partial` is set by `Rian.Lower`'s exhaustiveness check when the clause heads are
    **not** total (a function relying on a runtime no-match error, BEAM-style). The
    Rust emitter then appends a `_ => panic!(…)` fallthrough arm — the totality Rust's
    `match` requires — matching the BEAM `FunctionClauseError` / JS-JVM `throw` (so a
    partial function lowers to every target instead of being refused, ADR-0036).
    """
    @enforce_keys [:name, :params, :ret, :clauses]
    defstruct name: nil,
              params: [],
              ret: nil,
              clauses: [],
              pub?: false,
              tvars: [],
              bounds: %{},
              doc: nil,
              synthetic: false,
              test?: false,
              dispatch: nil,
              externals: %{},
              effects: [],
              partial: false

    @type t :: %__MODULE__{}
  end
end

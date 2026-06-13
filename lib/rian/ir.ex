defmodule Rian.IR do
  @moduledoc """
  The core intermediate representation — the typed structs the declaration
  parser (`Rian.Decl`) emits and the lowering backend (`Rian.Lower`) consumes.

  > **Superseded direction — ADR-0050.** The "expr/pattern stay tuples" stance below is
  > overturned (with evidence: the B1 triplication in `SELFHOST.md`, plus three incoming
  > emitters in ADR-0049). The target is **one typed sealed-sum core IR** that the checker and
  > *all* emitters consume, migrated incrementally. The description below reflects the
  > *current* (pre-migration) state.

  Declaration-level nodes are structs (below). **Expression and pattern** nodes
  remain the tuple AST that `Rian.Pratt` produces and the emitter/checker walk —
  that *is* the Expr/Pattern IR, kept as tuples because struct-ifying every
  arithmetic node would be churn without payoff:

      # Expr (Rian.Pratt output)
      {:num, "42"} · {:str, s} · {:id, x} · {:atom, a} · {:bin, op, l, r}
      {:unary, op, x} · {:call, f, args} · {:dot, head, name} · {:lambda, ps, body}
      {:if, c, t, e} · {:case, scrut, arms} · {:block, stmts}
      {:list_lit, elems, tail} · {:map_lit, pairs} · {:capture, _} · {:cap_arg, _}

      # Pattern (clause heads & case arms)
      :wild · {:var, name} · {:lit, value} · {:ctor, name, [pattern]} · {:tuple, [pattern]}
  """

  defmodule Field do
    @moduledoc "A variant/struct field: an optional compile-time `label` and a `type`."
    @enforce_keys [:type]
    defstruct [:label, :type]
  end

  defmodule Variant do
    @moduledoc "A sum-type variant: a constructor name and its (ordered) fields."
    @enforce_keys [:ctor]
    defstruct ctor: nil, fields: []
  end

  defmodule Type do
    @moduledoc "A sum-type declaration (`type Name := …`). `pub?` marks it exported from a `mod`."
    @enforce_keys [:name]
    defstruct name: nil, variants: [], pub?: false, doc: nil
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
  end

  defmodule Const do
    @moduledoc """
    A named compile-time constant (`const NAME Type := value`). `value` is the
    body source (parsed on lowering, like a function body). Lowers to a 0-arity
    accessor on the BEAM (`def`/`defp`) and a `const` on Rust; `pub?` exports it.
    """
    @enforce_keys [:name, :type, :value]
    defstruct name: nil, type: nil, value: nil, pub?: false, doc: nil
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
              structs: [],
              consts: [],
              funcs: [],
              doc: nil,
              targets: nil
  end

  defmodule Param do
    @moduledoc "A function parameter: `name`, `type`, reference `cap`ability."
    @enforce_keys [:name, :type]
    defstruct name: nil, type: nil, cap: :val
  end

  defmodule Clause do
    @moduledoc "One function clause: argument `pats`, a `body` (source string), an optional `guard` (source string)."
    @enforce_keys [:pats, :body]
    defstruct pats: [], body: nil, guard: nil
  end

  defmodule Func do
    @moduledoc """
    A function: `name`, `params`, return type `ret`, `clauses`. `pub?` marks it
    exported from a `mod`. `tvars` are the `forall` type-variable names (ADR-0042),
    empty for a non-generic function. `synthetic` marks a compiler-generated
    function — currently the `protocol` dispatcher (ADR-0042 §3/§6), which is
    **exempt from the exhaustiveness gate**: protocol dispatch is open by design
    (no case-arms, no totality requirement), unlike a user `case`. `test?` marks
    a `@test def` (ADR-0057) — a zero-arity `Bool` function the test runner
    (`Rian.Test`) executes and bridges to the host's xUnit framework.
    """
    @enforce_keys [:name, :params, :ret, :clauses]
    defstruct name: nil,
              params: [],
              ret: nil,
              clauses: [],
              pub?: false,
              tvars: [],
              doc: nil,
              synthetic: false,
              test?: false
  end
end

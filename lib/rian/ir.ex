defmodule Rian.IR do
  @moduledoc """
  The core intermediate representation — the typed structs the declaration
  parser (`Rian.Decl`) emits and the lowering backend (`Rian.Lower`) consumes.

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
    @moduledoc "A sum-type declaration (`type Name := …`)."
    @enforce_keys [:name]
    defstruct name: nil, variants: []
  end

  defmodule Struct do
    @moduledoc """
    A product-type declaration (`struct Name(field Type, …)`). Unlike a `Type`,
    which lowers to tagged tuples / a Rust `enum`, a `Struct` lowers to a named
    record on each target (`defstruct` on the BEAM, a `struct {…}` on Rust) and is
    built with constructor-call syntax (`Name(v1, v2)`).
    """
    @enforce_keys [:name]
    defstruct name: nil, fields: []
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
    @moduledoc "A function: `name`, `params`, return type `ret`, and `clauses`."
    @enforce_keys [:name, :params, :ret, :clauses]
    defstruct name: nil, params: [], ret: nil, clauses: []
  end
end

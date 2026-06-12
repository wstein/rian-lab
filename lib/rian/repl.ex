defmodule Rian.Repl do
  @moduledoc """
  The Rian REPL eval engine (ADR-0053) — a **compiling** REPL: every entry runs
  the real pipeline (`Lexer → Decl/Pratt → Check → Beam → :code.load_binary →
  eval`), never a side-interpreter, so what runs at the prompt passed the full
  gate and cannot diverge from the compiler.

  This module is the composable **read → eval → print** core (ADR-0053 §1):
  `eval/2` compiles and runs one entry against a `Session`; `render/1` is the
  print phase. The interactive loop ([`Mix.Tasks.Rian.Repl`](../mix/tasks/rian.repl.ex))
  and every future surface (Livebook, the web playground) reuse this engine, so
  none can drift from the real compiler.

  ## Session model (ADR-0053 §3)

  A session accumulates two things:

    * **declarations** (`def`/`type`/… units) — a new unit *redefines* any unit
      sharing a name (Clojure's `def` model; redefinition, not mutation);
    * **top-level `:=` bindings** — visible to subsequent *expressions* (not to
      function bodies, which stay closed); a new bind shadows an earlier one.

  An expression is evaluated by wrapping it as a polymorphic `def __repl__() T
  forall T` over the session's declarations and bindings, compiling the whole
  program, and calling it.

  Each session is backed by a **single** BEAM module (`rian_repl_<base>`) that
  is purged and reloaded on every eval, so a session's atom-table and code-
  memory footprint stay bounded regardless of how many entries it sees.

  ## Engine contract

  `eval/2` is **pure of IO**: it never reads stdin, never writes stdout/stderr,
  never logs. All output happens in the print phase (`render/1`), which returns
  a string — so any surface (the `mix rian.repl` loop, a Livebook smart-cell,
  the web playground) drives the engine without conflicting with the surface's
  own IO model. The no-IO property is asserted by `Rian.ReplTest`.

  ## Scope

  Whatever [`Rian.Beam`](beam.ex) compiles: functions, sum-variant construction
  and patterns, `case`/`if`, `when` guards, arithmetic, tuples, cons lists,
  maps, atoms, strings with `<>` concat, FFI calls, `with` error composition,
  and local calls. Constructs not yet lowered (currently `struct` declarations
  and bare field access `a.field`) raise a clear error — never a silent
  miscompile. Output is the value and its inferred type (ADR-0034), with a
  session function's declared return type threaded through local-call
  inference; the effect set (ADR-0048) joins once the effect checker lands.
  """

  alias Rian.{Beam, Check, Decl, Pratt}

  @decl_keywords ~w(def type struct alias const mod)

  defmodule Session do
    @moduledoc """
    REPL session state: accumulated `units` (declarations) and `binds`
    (top-level `:=`), plus a per-session `base` integer that names the
    session's one BEAM module (`rian_repl_<base>`). That module is purged
    and reloaded on every eval, so the atom table and code memory stay
    bounded for any session length.
    """
    @type unit :: {names :: [String.t()], src :: String.t()}
    @type bind :: {name :: String.t(), stmt_src :: String.t()}
    @type t :: %__MODULE__{
            units: [unit],
            binds: [bind],
            base: integer()
          }
    @enforce_keys [:base]
    defstruct units: [], binds: [], base: nil
  end

  @typedoc "Opaque session value driven by `new/0`, `eval/2`, and `render/1`."
  @type t :: Session.t()

  @typedoc """
  An eval outcome — what `eval/2` returns alongside the next session, and what
  `render/1` formats for display. Surfaces pattern-match on these directly.
  """
  @type result ::
          :empty
          | {:value, term(), String.t() | nil}
          | {:bound, String.t(), term(), String.t() | nil}
          | {:defined, [String.t()]}
          | {:error, String.t()}

  @doc "A fresh, empty session."
  @spec new() :: t()
  def new, do: %Session{base: :erlang.unique_integer([:positive])}

  @doc """
  Evaluate one entry against `session`. Returns `{result, session'}`; the session
  advances only on success (a failed entry leaves it unchanged).

  This function performs no IO — see the engine contract in the module doc.
  """
  @spec eval(t(), String.t()) :: {result(), t()}
  def eval(%Session{} = s, input) do
    cond do
      String.trim(input) == "" -> {:empty, s}
      declaration?(input) -> eval_decl(s, input)
      true -> eval_stmt(s, input)
    end
  end

  @doc "Render a `result` for display — the print phase (ADR-0053 §1)."
  @spec render(result()) :: String.t()
  def render(:empty), do: ""
  def render({:value, v, nil}), do: inspect(v)
  def render({:value, v, type}), do: "#{inspect(v)} : #{type}"
  def render({:bound, name, v, nil}), do: "#{name} := #{inspect(v)}"
  def render({:bound, name, v, type}), do: "#{name} := #{inspect(v)} : #{type}"
  def render({:defined, names}), do: "defined " <> Enum.join(names, ", ")
  def render({:error, message}), do: "error: " <> message

  # ── declarations ────────────────────────────────────────────────────────

  defp eval_decl(s, input) do
    names = decl_names(input)

    units =
      Enum.reject(s.units, fn {ns, _} -> Enum.any?(ns, &(&1 in names)) end) ++
        [{names, String.trim(input)}]

    _module = reload(s, units_src(units))
    {{:defined, names}, %{s | units: units}}
  rescue
    e -> {{:error, Exception.message(e)}, s}
  end

  # ── statements: a top-level bind, or an expression ──────────────────────

  defp eval_stmt(s, input) do
    case safe_parse_body(input) do
      {:ok, {:block, [{:bind, name, rhs}]}} -> eval_bind(s, input, name, rhs)
      {:ok, _block} -> eval_expr(s, input)
      {:error, message} -> {{:error, message}, s}
    end
  end

  defp eval_bind(s, input, name, rhs) do
    ic = session_ic(s)
    type = safe_infer(rhs, bind_env(s.binds, ic), ic)
    binds = Enum.reject(s.binds, fn {n, _} -> n == name end) ++ [{name, String.trim(input)}]

    case run(s, binds, s.units, name) do
      {:ok, value} -> {{:bound, name, value, type}, %{s | binds: binds}}
      {:error, message} -> {{:error, message}, s}
    end
  end

  defp eval_expr(s, input) do
    ic = session_ic(s)
    type = safe_infer_input(input, bind_env(s.binds, ic), ic)

    case run(s, s.binds, s.units, input) do
      {:ok, value} -> {{:value, value, type}, s}
      {:error, message} -> {{:error, message}, s}
    end
  end

  # ── the compile + eval core ─────────────────────────────────────────────

  defp run(s, binds, units, expr_src) do
    module = reload(s, program(units, binds, expr_src))
    {:ok, apply(module, :__repl__, [])}
  rescue
    e -> {:error, Exception.message(e)}
  end

  # Purge the session's prior module version and load the new source under the
  # same name. One module per session — keeps the atom table and code memory
  # bounded no matter how many entries the session sees.
  defp reload(s, src) do
    module = module_name(s)
    _ = :code.purge(module)
    _ = :code.delete(module)
    {:ok, ^module} = Beam.load(src, module)
    module
  end

  # Wrap `expr_src` as a polymorphic 0-arity function over the session's
  # declarations and bindings. `T forall T` is a sound "any return type" (a
  # genuinely polymorphic return, ADR-0042) — not a checker lie. Rian is not
  # whitespace-sensitive, so lines are emitted unindented.
  defp program(units, binds, expr_src) do
    lines = Enum.map(binds, fn {_name, stmt} -> stmt end) ++ [expr_src]
    wrapper = "def __repl__() T forall T\n" <> Enum.join(lines, "\n") <> "\nend"

    case units_src(units) do
      "" -> wrapper
      u -> u <> "\n\n" <> wrapper
    end
  end

  # ── helpers ─────────────────────────────────────────────────────────────

  defp declaration?(input),
    do: Regex.match?(~r/\A\s*(#{Enum.join(@decl_keywords, "|")})\b/, input)

  defp decl_names(input) do
    prog = Decl.parse(input)

    [prog.funcs, prog.types, prog.structs, Map.get(prog, :mods, [])]
    |> Enum.flat_map(fn list -> Enum.map(list, & &1.name) end)
    |> Enum.uniq()
  end

  defp units_src(units), do: Enum.map_join(units, "\n\n", fn {_names, src} -> src end)

  defp module_name(%Session{base: base}), do: String.to_atom("rian_repl_#{base}")

  defp safe_parse_body(input) do
    {:ok, Pratt.parse_body(input)}
  rescue
    e -> {:error, Exception.message(e)}
  end

  # A type env for inference: each bind's name mapped to its inferred type.
  # The session's `ic` is threaded in so a bind whose RHS calls a session
  # function (`y := sq(3)`) records the function's declared return type, not
  # `:unknown`.
  defp bind_env(binds, ic) do
    Enum.reduce(binds, %{}, fn {name, stmt}, acc ->
      case safe_parse_body(stmt) do
        {:ok, {:block, [{:bind, ^name, rhs}]}} ->
          Map.put(acc, name, infer_or_unknown(rhs, acc, ic))

        _ ->
          acc
      end
    end)
  end

  # Build an inference context from the session's declarations so calls to
  # session-defined functions (`sq(9) : Int64`) and sum-type constructors
  # (`One : Bit`) infer concretely instead of falling back to `:unknown`.
  # A malformed accumulated program yields an empty `ic` — a bare expression
  # still infers, just without session-level knowledge.
  defp session_ic(%Session{units: []}), do: %{}

  defp session_ic(%Session{units: units}) do
    Check.program_ic(Decl.parse(units_src(units)))
  rescue
    _ -> %{}
  end

  defp safe_infer_input(input, env, ic) do
    case safe_parse_body(input) do
      {:ok, {:block, [{:expr, e}]}} -> safe_infer(e, env, ic)
      {:ok, {:block, [{:bind, _name, e}]}} -> safe_infer(e, env, ic)
      _ -> nil
    end
  end

  defp safe_infer(ast, env, ic) do
    case infer_or_unknown(ast, env, ic) do
      type when is_binary(type) -> type
      _ -> nil
    end
  end

  defp infer_or_unknown(ast, env, ic) do
    Check.infer(ast, env, ic)
  rescue
    _ -> :unknown
  end
end

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

  ## Scope

  Whatever [`Rian.Beam`](beam.ex) compiles: functions, sum-variant construction
  and patterns, `case`/`if`, `when` guards, arithmetic, tuples, cons lists,
  atoms, local calls. Constructs outside that set (strings, `struct`, FFI,
  `with`) raise a clear error — never a silent miscompile. Output is the value
  and its inferred type (ADR-0034); the effect set (ADR-0048) joins once the
  effect checker lands.
  """

  alias Rian.{Beam, Check, Decl, Pratt}

  @decl_keywords ~w(def type struct alias const mod)

  defmodule Session do
    @moduledoc """
    REPL session state: accumulated `units` (declarations) and `binds`
    (top-level `:=`), a per-session `base` and per-eval `counter` that name a
    fresh module each compile (avoiding code-reload churn).
    """
    @type unit :: {names :: [String.t()], src :: String.t()}
    @type bind :: {name :: String.t(), stmt_src :: String.t()}
    @type t :: %__MODULE__{
            units: [unit],
            binds: [bind],
            base: integer(),
            counter: non_neg_integer()
          }
    @enforce_keys [:base]
    defstruct units: [], binds: [], base: nil, counter: 0
  end

  @type result ::
          :empty
          | {:value, term(), String.t() | nil}
          | {:bound, String.t(), term(), String.t() | nil}
          | {:defined, [String.t()]}
          | {:error, String.t()}

  @doc "A fresh, empty session."
  @spec new() :: Session.t()
  def new, do: %Session{base: :erlang.unique_integer([:positive])}

  @doc """
  Evaluate one entry against `session`. Returns `{result, session'}`; the session
  advances only on success (a failed entry leaves it unchanged).
  """
  @spec eval(Session.t(), String.t()) :: {result, Session.t()}
  def eval(%Session{} = s, input) do
    cond do
      String.trim(input) == "" -> {:empty, s}
      declaration?(input) -> eval_decl(s, input)
      true -> eval_stmt(s, input)
    end
  end

  @doc "Render a `result` for display — the print phase (ADR-0053 §1)."
  @spec render(result) :: String.t()
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

    module = module_name(s)

    {:ok, ^module} = Beam.load(units_src(units), module)
    {{:defined, names}, %{s | units: units, counter: s.counter + 1}}
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
    type = safe_infer(rhs, bind_env(s.binds))
    binds = Enum.reject(s.binds, fn {n, _} -> n == name end) ++ [{name, String.trim(input)}]

    case run(s, binds, s.units, name) do
      {:ok, value, counter} ->
        {{:bound, name, value, type}, %{s | binds: binds, counter: counter}}

      {:error, message} ->
        {{:error, message}, s}
    end
  end

  defp eval_expr(s, input) do
    type = safe_infer_input(input, bind_env(s.binds))

    case run(s, s.binds, s.units, input) do
      {:ok, value, counter} -> {{:value, value, type}, %{s | counter: counter}}
      {:error, message} -> {{:error, message}, s}
    end
  end

  # ── the compile + eval core ─────────────────────────────────────────────

  defp run(s, binds, units, expr_src) do
    module = module_name(s)
    {:ok, ^module} = Beam.load(program(units, binds, expr_src), module)
    {:ok, apply(module, :__repl__, []), s.counter + 1}
  rescue
    e -> {:error, Exception.message(e)}
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

  defp module_name(%Session{base: base, counter: counter}),
    do: String.to_atom("rian_repl_#{base}_#{counter}")

  defp safe_parse_body(input) do
    {:ok, Pratt.parse_body(input)}
  rescue
    e -> {:error, Exception.message(e)}
  end

  # A type env for inference: each bind's name mapped to its inferred type.
  defp bind_env(binds) do
    Enum.reduce(binds, %{}, fn {name, stmt}, acc ->
      case safe_parse_body(stmt) do
        {:ok, {:block, [{:bind, ^name, rhs}]}} -> Map.put(acc, name, infer_or_unknown(rhs, acc))
        _ -> acc
      end
    end)
  end

  defp safe_infer_input(input, env) do
    case safe_parse_body(input) do
      {:ok, {:block, [{:expr, e}]}} -> safe_infer(e, env)
      {:ok, {:block, [{:bind, _name, e}]}} -> safe_infer(e, env)
      _ -> nil
    end
  end

  defp safe_infer(ast, env) do
    case infer_or_unknown(ast, env) do
      type when is_binary(type) -> type
      _ -> nil
    end
  end

  defp infer_or_unknown(ast, env) do
    Check.infer(ast, env, %{})
  rescue
    _ -> :unknown
  end
end

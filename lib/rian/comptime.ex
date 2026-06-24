defmodule Rian.Comptime do
  @moduledoc """
  `comptime(expr)` — Zig-style compile-time evaluation. The expression is
  evaluated at compile time and replaced by its literal value.

  The evaluator is a PURE SANDBOX (ADR-0009): only literals, arithmetic, and
  the boolean/comparison operators are permitted. Function calls, identifiers
  (non-constants), and any effectful node are REFUSED — a comptime block can
  never run FFI or perform build-time effects unless a build capability is
  explicitly granted (deferred). Runs as an AST -> AST pass.
  """
  use Rian.Ann

  alias Rian.Macro

  @rian_sig "pub def fold(node Expr) Expr"
  @spec fold(term()) :: term()
  # EXPLICIT `comptime(expr)` — forces folding and RAISES on a non-constant or non-pure
  # expression (the guarantee the user opted into). The sandbox is deliberately loose: a mixed
  # `Int * Float` folds here (`comptime(3.14 * 2)` → `6.28`) even though regular code rejects it,
  # because the call is an explicit escape hatch.
  def fold({:call, {:id, "comptime"}, [e]}) do
    case eval(e) do
      {:ok, v} -> to_literal(v)
      {:error, reason} -> raise "comptime: #{reason}"
    end
  end

  def fold(node), do: Macro.map_node(node, &fold/1)

  @rian_sig "pub def fold_constants(node Expr) Expr"
  @spec fold_constants(term()) :: term()
  @doc """
  AUTOMATIC constant folding (ADR-0046, "compile-time by default"): a pure `+ - * / div rem` /
  comparison / boolean expression whose operands are all literals is replaced by its literal —
  `2 + 3 * 4` → `14`, before the program ever runs. Unlike `comptime`, it is OPPORTUNISTIC (a
  non-constant operand just leaves the node) and TYPE-PRESERVING: it folds only when the numeric
  literals are kind-homogeneous (all `Int`, or all `Float`), so it never folds a mixed `Int * Float`
  — which the checker rejects (ADR-0034/0035) — and thus never masks a type error. (`6 / 2` → `3.0`
  is fine: `/` is float division, the checker agrees.) A distinct program-tail pass (so the parity
  `assemble`/`dcl` streams, which stop before the tail, are unfolded; the `--no-fold` flag skips it).
  """
  def fold_constants({:bin, op, l, r}), do: fold_bin(op, fold_constants(l), fold_constants(r))

  def fold_constants({:unary, op, x}) when op in ["-", "not"],
    do: fold_eval({:unary, op, fold_constants(x)})

  def fold_constants(node), do: Macro.map_node(node, &fold_constants/1)

  @doc "Is `node` a constant literal (num / string / `Char` / `true`/`false`)?"
  @rian_sig "pub def literal?(node Expr) Bool"
  @spec literal?(term()) :: boolean()
  def literal?({:num, _}), do: true
  def literal?({:str, _}), do: true
  def literal?({:char, _}), do: true
  def literal?({:id, b}) when b in ["true", "false"], do: true
  def literal?(_), do: false

  @doc "Unwrap a single-expression block `{:block, [{:expr, e}]}` to `e` (else identity)."
  @rian_sig "pub def unwrap_block(node Expr) Expr"
  @spec unwrap_block(term()) :: term()
  def unwrap_block({:block, [{:expr, e}]}), do: e
  def unwrap_block(node), do: node

  @doc """
  Substitute `subst` (param name → value AST) into `body` everywhere. Sound only on a binder-free
  body (see `inlinable_body?`), so no `{:id, p}` reference is ever a shadowed binding.
  """
  @rian_sig "pub def substitute(body Expr, subst Dict(String, Expr)) Expr"
  @spec substitute(term(), map()) :: term()
  def substitute({:id, name} = node, subst), do: Map.get(subst, name, node)

  def substitute(node, subst) when is_tuple(node),
    do: node |> Tuple.to_list() |> Enum.map(&substitute(&1, subst)) |> List.to_tuple()

  def substitute(node, subst) when is_list(node), do: Enum.map(node, &substitute(&1, subst))
  def substitute(node, _subst), do: node

  @doc """
  Is a function body safe to inline by substituting its params? — true iff it is BINDER-FREE (no
  `:=`/`lambda`/`case`/`with`), so substituting `{:id, param}` can never land in a scope that
  shadows the param. Used by the inlinable-function registry (`Rian.Decl.fold_constants_pass`).
  """
  @rian_sig "pub def inlinable_body?(node Expr) Bool"
  @spec inlinable_body?(term()) :: boolean()
  def inlinable_body?(node), do: not has_binders?(node)

  defp has_binders?({:bind, _, _}), do: true
  defp has_binders?({:typed_bind, _, _, _}), do: true
  defp has_binders?({:lambda, _, _}), do: true
  defp has_binders?({:case, _, _}), do: true
  defp has_binders?({:with, _, _, _}), do: true

  defp has_binders?(node) when is_tuple(node),
    do: node |> Tuple.to_list() |> Enum.any?(&has_binders?/1)

  defp has_binders?(node) when is_list(node), do: Enum.any?(node, &has_binders?/1)
  defp has_binders?(_), do: false

  # operands are folded first; then simplify by operator.
  # `<>` over two string literals concatenates at compile time (`"a" <> "b"` → `"ab"`). Both operands
  # are literals — no variable — so nothing the checker/InferLocal/Reach derive from the node is lost.
  defp fold_bin("<>", {:str, a}, {:str, b}), do: {:str, a <> b}

  # everything else: a numeric / comparison / fully-constant `and`/`or` eval that fires only when BOTH
  # operands are now constant + kind-homogeneous, else the node passes through (operands folded). Note
  # the deliberately-absent boolean IDENTITIES (`true and x` → `x`): removing an operator over a
  # VARIABLE would drop the `Bool` constraint InferLocal reads from it and the operator pin Reach reads
  # — a pre-checker pass must stay variable-neutral (those simplifications belong in a post-check pass).
  defp fold_bin(op, l, r), do: fold_eval({:bin, op, l, r})

  defp fold_eval(node) do
    with true <- homogeneous_nums?(node),
         {:ok, v} <- eval(node) do
      to_literal(v)
    else
      _ -> node
    end
  end

  defp to_literal(v) when is_integer(v), do: {:num, Integer.to_string(v)}
  defp to_literal(v) when is_float(v), do: {:num, Float.to_string(v)}
  defp to_literal(true), do: {:id, "true"}
  defp to_literal(false), do: {:id, "false"}

  # Are all numeric literals in `node` the same kind (all int OR all float)? A mixed set means a
  # cross-kind operation the checker would reject — refuse to fold it. No numeric literals (a pure
  # boolean expression) is vacuously homogeneous.
  defp homogeneous_nums?(node), do: node |> num_kinds() |> Enum.uniq() |> length() <= 1

  defp num_kinds({:num, n}), do: [num_kind(n)]

  defp num_kinds(node) when is_tuple(node),
    do: node |> Tuple.to_list() |> Enum.flat_map(&num_kinds/1)

  defp num_kinds(node) when is_list(node), do: Enum.flat_map(node, &num_kinds/1)
  defp num_kinds(_), do: []

  defp num_kind(n) do
    clean = String.replace(n, "_", "")
    if String.contains?(clean, ".") or String.match?(clean, ~r/[eE]/), do: :float, else: :int
  end

  # ── pure sandboxed evaluator ───────────────────────────────────────────
  defp eval({:num, n}) do
    clean = String.replace(n, "_", "")

    if String.contains?(clean, ".") or String.match?(clean, ~r/[eE]/),
      do: {:ok, String.to_float(clean)},
      else: {:ok, String.to_integer(clean)}
  end

  defp eval({:unary, "-", x}) do
    with {:ok, a} <- eval(x), do: {:ok, -a}
  end

  defp eval({:unary, "not", x}) do
    with {:ok, a} <- eval(x), do: {:ok, not truthy!(a)}
  end

  defp eval({:bin, op, l, r}) do
    with {:ok, a} <- eval(l), {:ok, b} <- eval(r) do
      case op do
        "+" -> {:ok, a + b}
        "-" -> {:ok, a - b}
        "*" -> {:ok, a * b}
        "/" -> if b == 0, do: {:error, "division by zero"}, else: {:ok, a / b}
        "div" -> int_div(a, b, &div/2)
        "rem" -> int_div(a, b, &rem/2)
        "<" -> {:ok, a < b}
        "<=" -> {:ok, a <= b}
        ">" -> {:ok, a > b}
        ">=" -> {:ok, a >= b}
        "==" -> {:ok, a == b}
        "!=" -> {:ok, a != b}
        "and" -> bool_op(a, b, &(&1 and &2))
        "or" -> bool_op(a, b, &(&1 or &2))
        _ -> {:error, "operator `#{op}` not allowed in comptime"}
      end
    end
  end

  defp eval({:call, _, _}), do: {:error, "calls are not allowed in a pure comptime sandbox"}
  defp eval({:id, "true"}), do: {:ok, true}
  defp eval({:id, "false"}), do: {:ok, false}
  defp eval({:id, x}), do: {:error, "`#{x}` is not a compile-time constant"}
  defp eval({:dot, _, _}), do: {:error, "FFI/field access is not allowed in comptime"}
  defp eval(other), do: {:error, "unsupported in comptime: #{inspect(other)}"}

  defp bool_op(a, b, f) when is_boolean(a) and is_boolean(b), do: {:ok, f.(a, b)}
  defp bool_op(_a, _b, _f), do: {:error, "`and`/`or` require booleans"}

  # `div`/`rem` are integer-only (mirrors the language: `/` is float division).
  defp int_div(_a, 0, _op), do: {:error, "division by zero"}
  defp int_div(a, b, op) when is_integer(a) and is_integer(b), do: {:ok, op.(a, b)}
  defp int_div(_a, _b, _op), do: {:error, "`div`/`rem` require integer operands"}

  defp truthy!(b) when is_boolean(b), do: b
  defp truthy!(_), do: raise("comptime: `not` expects a boolean")
end

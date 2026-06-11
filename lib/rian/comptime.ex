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
  alias Rian.Macro

  def fold({:call, {:id, "comptime"}, [e]}) do
    case eval(e) do
      {:ok, v} when is_integer(v) -> {:num, Integer.to_string(v)}
      {:ok, true} -> {:id, "true"}
      {:ok, false} -> {:id, "false"}
      {:error, reason} -> raise "comptime: #{reason}"
    end
  end

  def fold(node), do: Macro.map_node(node, &fold/1)

  # ── pure sandboxed evaluator ───────────────────────────────────────────
  defp eval({:num, n}), do: {:ok, String.to_integer(n)}

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
        "div" -> if b == 0, do: {:error, "division by zero"}, else: {:ok, div(a, b)}
        "rem" -> if b == 0, do: {:error, "division by zero"}, else: {:ok, rem(a, b)}
        "<" -> {:ok, a < b}
        "<=" -> {:ok, a <= b}
        ">" -> {:ok, a > b}
        ">=" -> {:ok, a >= b}
        "==" -> {:ok, a == b}
        "!=" -> {:ok, a != b}
        _ -> {:error, "operator `#{op}` not allowed in comptime"}
      end
    end
  end

  defp eval({:call, _, _}), do: {:error, "calls are not allowed in a pure comptime sandbox"}
  defp eval({:id, x}), do: {:error, "`#{x}` is not a compile-time constant"}
  defp eval({:dot, _, _}), do: {:error, "FFI/field access is not allowed in comptime"}
  defp eval(other), do: {:error, "unsupported in comptime: #{inspect(other)}"}

  defp truthy!(b) when is_boolean(b), do: b
  defp truthy!(_), do: raise("comptime: `not` expects a boolean")
end

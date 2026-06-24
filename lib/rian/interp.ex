defmodule Rian.Interp do
  @moduledoc """
  String-interpolation resolution (ADR-0069).

  `Rian.Pratt` parses `"… ${expr} …"` into a `{:str_interp, parts}` surface node.
  This pass — run **program-wide** after assembly (`Rian.Decl.resolve_interp/1`, once
  macro/`comptime` have fired per scope) — rewrites each node into a plain `<>`/
  stringify chain *before* the checker and every emitter see it. So there is **no
  new Core node and no per-emitter `{:str_interp}` handling**: the result is an
  ordinary `{:bin, "<>", …}` tree the existing machinery already lowers.

  Each hole is stringified by its **statically inferred type** (interpolation is
  monomorphic per call site, ADR-0069 §4 — so no runtime `Show` dispatch and none
  of the BEAM/JS dispatch-guard collision the ADR flags). Because the pass runs
  program-wide, its `ic` carries **every module's** signatures, types, structs and
  ctors (not just the enclosing scope's) plus the clause's parameter types — so a
  hole over a *call result* (`${double(2)}`, a generic `${id(7)}`), a **cross-module**
  call (`${OtherMod.f(x)}`), or a cross-module struct field resolves its declared/
  instantiated return type — not only literals and same-scope params. The `ic` also
  folds in **call-result return inference** (`Rian.Check.fill_local_rets/2`): an
  un-annotated local function's return is inferred from its body, so `${tag(n)}` over
  `def tag(s) := s <> "!"` resolves to `String` without an explicit return type. And
  the resolver is **scope-aware** — a hole inside a `case` arm or after a block `:=`
  bind sees those names typed (an arm pattern binds against the scrutinee's type),
  the same env-threading `Rian.Check.annotate` does. In particular a **value-union
  type-pattern** (`n Int53 ->`, ADR-0083) binds the binder to the *matched member*
  type, so `${n}` resolves by that member (`__prim_int_to_string`, portable to every
  target) — not the `__prim_to_string` runtime-`Show` fallback, which has no Rust
  `Display` and would pin the function off `:rs`:

    * `String`            → the value itself (identity)
    * `Int`/`Int*`/`UInt*`→ `__prim_int_to_string(value)` (lowered natively per target)
    * `Bool`              → `if value do "true" else "false" end`
    * `Char`              → `__prim_char_to_string(value)` (the codepoint's single
                            character; byte-identical per target — the static type
                            means no runtime Char/Int dispatch, ADR-0069 §6)
    * `Float64`           → `Show.float(value)` — the portable ECMAScript
                            `Number::toString` formatter (examples/rian/stdlib_show.rian),
                            **auto-injected** into the program when first interpolated
                            (`Rian.Decl.inject_stdlib/1`), so it needs no explicit
                            import. Reaches all four targets, **byte-identical on
                            every one** — `:ex`/`:rs`/`:js`/`:jvm` (ADR-0069 §6).
    * a **user type `T`**  with an `impl Show for T` → `show(value)`: the program's
                            `Show` dispatcher routes it to the impl (ADR-0069 §6, user
                            `Show`). The hole's static type fixes `T`, so this is still
                            monomorphic. Reaches as far as the impl does — a sum-dispatch
                            consumer is `[:ex, :js]` (the constructor-tag atom pins off
                            `:rs`/`:jvm`), honestly via `Rian.Reach`.

  `Float32`, a user type with **no** `impl Show`, and a hole whose type cannot be
  inferred are a **compile error at the hole** — never a silent `inspect`-style
  fallback (ADR-0035). (`Float32` has no portable formatter; widen to `Float64` and
  interpolate that.) A hole whose type is the `_Unk` transpiler-draft marker is
  **deferred** (passed through unchanged), not errored — a genuine `:unknown` is not.
  A **field-access hole** (`${p.name}`) now resolves to the field's declared type when
  `p`'s type is a single-variant struct (`Rian.Check` `:fields` table); over a `_Unk`
  draft value the access stays `_Unk` (and so defers), and `.f` on a value whose sum
  variant is not statically known still infers `:unknown` (narrow with `case` first).
  """
  use Rian.Ann

  alias Rian.Check

  # `env` is the checker's type environment (name -> type), the same `Dict(String,
  # String)` threaded through `Rian.Check.infer/3`. `show` is genuinely a *set* of
  # type names (a `MapSet`); Rian has no `Set(T)` type yet, so it is an honest
  # `_Unk` ("type still to be defined", ADR-0034) — not `Any`, and not a `Vec`,
  # which would imply order/duplicates it does not have.
  @rian_sig "pub def resolve(ast Expr, env Dict(String, String), ic Ic) Expr"
  @rian_sig "pub def resolve(ast Expr, env Dict(String, String), ic Ic, show _Unk) Expr"
  @doc """
  Rewrite every `{:str_interp, …}` in `ast` to a `<>`/stringify chain.

  `show` is the set of type names with an `impl Show for T` in the program — a hole
  of such a type lowers to `show(value)` (the protocol dispatcher routes it to the
  impl; ADR-0069 §6, user `Show`). It is statically resolved, so still monomorphic.
  """
  @spec resolve(term(), map(), map(), term()) :: term()
  def resolve(ast, env, ic, show \\ MapSet.new())

  def resolve({:str_interp, parts}, env, ic, show) do
    parts
    |> Enum.map(&resolve_part(&1, env, ic, show))
    |> concat_chain()
  end

  # Scope-aware descent (ADR-0069 §4): a hole inside a `case` arm or after a block
  # `:=` bind must see the names those scopes introduce, typed, or it degrades to
  # `:unknown`. Thread the env the same way `Rian.Check.annotate` does — each arm
  # pattern binds against the scrutinee's inferred type; each `:=` extends the env
  # for the statements that follow. Placed before the generic tuple/list walk, which
  # would otherwise descend with the *outer* env and lose these bindings.
  def resolve({:case, scrut, arms}, env, ic, show) do
    scrut2 = resolve(scrut, env, ic, show)
    st = Check.infer(scrut2, env, ic)

    arms2 =
      Enum.map(arms, fn {pat, guard, body} ->
        env2 = Map.merge(env, pat_bindings(pat, st))
        guard2 = if guard, do: resolve(guard, env2, ic, show), else: guard
        {pat, guard2, resolve(body, env2, ic, show)}
      end)

    {:case, scrut2, arms2}
  end

  def resolve({:block, stmts}, env, ic, show) do
    {rev, _env} =
      Enum.reduce(stmts, {[], env}, fn stmt, {acc, e} ->
        case stmt do
          {:bind, n, ex} ->
            ex2 = resolve(ex, e, ic, show)
            {[{:bind, n, ex2} | acc], Map.put(e, n, Check.infer(ex2, e, ic))}

          {:typed_bind, n, t, ex} ->
            {[{:typed_bind, n, t, resolve(ex, e, ic, show)} | acc], Map.put(e, n, t)}

          {:expr, ex} ->
            {[{:expr, resolve(ex, e, ic, show)} | acc], e}

          other ->
            {[resolve(other, e, ic, show) | acc], e}
        end
      end)

    {:block, Enum.reverse(rev)}
  end

  def resolve(ast, env, ic, show) when is_tuple(ast),
    do: ast |> Tuple.to_list() |> Enum.map(&resolve(&1, env, ic, show)) |> List.to_tuple()

  def resolve(list, env, ic, show) when is_list(list),
    do: Enum.map(list, &resolve(&1, env, ic, show))

  def resolve(other, _env, _ic, _show), do: other

  # Names a surface `case`-arm pattern introduces, typed for interpolation. A bare
  # variable binds to the whole scrutinee type (`alts -> …${alts}` where the
  # scrutinee is `String`); an `x @ pat` alias binds `x` likewise and descends. Any
  # destructuring pattern's inner vars are bound `:unknown` (their component types
  # aren't recovered here — sound: a hole over one still errors/defers as before, no
  # worse than the prior constant-env behaviour).
  defp pat_bindings({:var, x}, st), do: %{x => st}
  defp pat_bindings({:as, x, pat}, st), do: Map.put(pat_bindings(pat, :unknown), x, st)
  defp pat_bindings({:bind, x, pat}, st), do: Map.put(pat_bindings(pat, :unknown), x, st)

  # a value-union type-pattern `name Type` (ADR-0083) binds `name` to the MATCHED member
  # type, not the scrutinee's (union) type — mirroring `Rian.Check.narrow(%PTyped{})`. This
  # is what lets a hole inside a union arm (`n Int53 -> "${n}"`) resolve by the concrete
  # member (`__prim_int_to_string`, portable to every target) instead of the `__prim_to_string`
  # runtime-`Show` fallback (which pins the function off `:rs`). (ADR-0069 §4 + ADR-0083.)
  defp pat_bindings({:typed, name, tname}, _st), do: %{name => tname}
  defp pat_bindings({:typed, name, tname, _disc}, _st), do: %{name => tname}

  defp pat_bindings(pat, _st) when is_tuple(pat),
    do: pat |> Tuple.to_list() |> Enum.reduce(%{}, &Map.merge(&2, pat_bindings(&1, :unknown)))

  defp pat_bindings(pats, _st) when is_list(pats),
    do: Enum.reduce(pats, %{}, &Map.merge(&2, pat_bindings(&1, :unknown)))

  defp pat_bindings(_pat, _st), do: %{}

  @spec resolve_part(tuple(), map(), map(), term()) :: tuple()
  defp resolve_part({:lit, s}, _env, _ic, _show), do: {:str, s}

  defp resolve_part({:hole, expr}, env, ic, show) do
    # resolve nested interpolation first, then stringify by the hole's type
    expr = resolve(expr, env, ic, show)

    # a hole that is now a CONSTANT literal (ADR-0046 auto-fold turned `${2 + 3 * 4}` into `${14}`)
    # is stringified at COMPILE time and baked into the template — `concat_chain` then merges it into
    # the neighbouring text, so `"calc = ${2 + 3 * 4}"` becomes the single literal `"calc = 14"`. The
    # baked repr is exactly what the runtime stringifier would produce (Int/Bool/Char are unambiguous;
    # Float is NOT baked — it needs the `Show.float` formatter, so it stays a runtime call).
    case bake_const(expr) do
      {:ok, s} -> {:str, s}
      :no -> stringify(expr, Check.infer(expr, env, ic), show)
    end
  end

  defp bake_const({:num, n}) do
    clean = String.replace(n, "_", "")

    # an INT literal's decimal digits ARE its `__prim_int_to_string` repr (auto-fold emits
    # `Integer.to_string`, so no leading zeros); a FLOAT needs the `Show.float` formatter — don't bake.
    if String.contains?(clean, ".") or String.match?(clean, ~r/[eE]/),
      do: :no,
      else: {:ok, clean}
  end

  defp bake_const({:id, "true"}), do: {:ok, "true"}
  defp bake_const({:id, "false"}), do: {:ok, "false"}
  defp bake_const({:char, cp}), do: {:ok, <<cp::utf8>>}
  defp bake_const(_), do: :no

  defp stringify(expr, "String", _show), do: expr

  defp stringify(expr, "Bool", _show),
    do: {:if, expr, {:block, [expr: {:str, "true"}]}, {:block, [expr: {:str, "false"}]}}

  # a `Symbol` (atom) is stringifiable at runtime — its name. Atoms are BEAM-only, so the
  # value (and any caller) is already `:ex`-pinned by Reach; lower via the runtime
  # stringifier `Prim.to_string` (BEAM `String.Chars.to_string`). (ADR-0069 §2.)
  defp stringify(expr, "Symbol", _show),
    do: {:call, {:id, "__prim_to_string"}, [expr]}

  # The `_Unk` **transpiler-draft marker** is an explicit "type not yet supplied" hole, not
  # a stringifiability verdict — so the resolver **defers** it (the value passes through the
  # `<>` chain unchanged: no `to_string`, no coercion) rather than erroring, letting a draft
  # parse.
  defp stringify(expr, "_Unk", _show), do: expr

  # A genuine `:unknown` (the checker *failed* to infer a real program's type — an un-pinned
  # matcher arg, an unbound var, a host/pipe-chain return) **falls through to runtime `Show`**
  # rather than erroring: emit `Prim.to_string` (the host's native runtime stringifier —
  # BEAM `String.Chars.to_string`, JS `String(x)`, JVM `x.toString()`). This honours the
  # checker's own contract ("infer `:unknown`, error only on a *provable* mismatch", ADR-0069
  # §2) — erroring on a merely-undetermined type proves nothing. There is no universal Rust
  # `Display`, so `Rian.Reach` pins any caller off `:rs` (`to_string_prim_blocker`); the gate
  # stays honest. A *determined* non-stringifiable type (`Float32`, a user type with no `impl
  # Show`) still hard-errors below — that is a provable verdict. (2026-06 reversal of the
  # earlier "`:unknown` is a hard error" consensus: a real inference gap deserves runtime
  # dispatch, not a parse-time refusal, especially for transpiler-draft compiler sources.)
  #
  # `:infer` is the same case, one pass earlier: an un-annotated *private* param still
  # carries the `:infer` marker here because `resolve_interp` runs *before* `InferLocal`
  # fills it (ADR-0034). Its type is genuinely undetermined at interp time → runtime `Show`,
  # exactly like `:unknown` (the value is whatever the resolved param turns out to be).
  # `Any` (the explicit dynamic top, ADR-0034) is the same: a value of unknown-at-compile
  # type → runtime `Show` (`Prim.to_string`); the function is already off `:rs` via `Any`.
  defp stringify(expr, t, _show) when t in [:unknown, :infer, "Any"],
    do: {:call, {:id, "__prim_to_string"}, [expr]}

  defp stringify(expr, type, show) do
    cond do
      int_type?(type) ->
        {:call, {:id, "__prim_int_to_string"}, [expr]}

      type == "Char" ->
        # the hole's type is known statically here, so there is no runtime Char/Int
        # dispatch (ADR-0069 §6) — emit the codepoint→string prim directly. A Char's
        # single-character string is byte-identical on every target.
        {:call, {:id, "__prim_char_to_string"}, [expr]}

      type == "Float64" ->
        # the canonical portable ECMAScript formatter (`Show.float`, ADR-0069 §6).
        # Emitting this call is the *only* signal that the program needs the `Show`
        # stdlib module — `Rian.Decl.inject_stdlib/1` supplies it by inspecting the
        # rewritten program for this call, so this pass stays a pure function (no
        # process-dict side-channel).
        {:call, {:dot, {:id, "Show"}, "float"}, [expr]}

      type == "Float32" ->
        raise ArgumentError,
              "interpolation of a `Float32` is not supported — widen to `Float64` and " <>
                "interpolate that (`Show.float` is the portable Float64 formatter, ADR-0069)"

      MapSet.member?(show, type) ->
        # a user type with an `impl Show for T` (ADR-0069 §6, user `Show`): call the
        # protocol method `show/1`. The hole's static type fixes T, so this stays
        # monomorphic — the program's `Show` dispatcher routes it to T's impl.
        {:call, {:id, "show"}, [expr]}

      true ->
        raise ArgumentError,
              "no `Show` for `#{type}` — interpolation requires a statically-known " <>
                "stringifiable type (String / Int* / Bool / Float64, or a type with an " <>
                "`impl Show`); got `#{type}`"
    end
  end

  # join the resolved parts into one string. Empty string *literals* (the lexer
  # emits a trailing `{:lit, ""}`, and adjacent holes leave `""` between them) are
  # dropped — they are identity for concatenation and only clutter the output.
  # ≥2 parts lower to a single-shot `__prim_str_concat_all` (one allocation: a
  # single BEAM binary / `format!` on Rust) rather than a left-nested `<>` cascade
  # that builds N−1 intermediates (ADR-0069 §6). One part is the value itself.
  defp concat_chain(parts) do
    case parts |> merge_strs() |> Enum.reject(&match?({:str, ""}, &1)) do
      [] -> {:str, ""}
      [only] -> only
      many -> {:call, {:id, "__prim_str_concat_all"}, many}
    end
  end

  # fold consecutive string-literal parts into one — so a compile-time-baked constant hole
  # (`bake_const`) merges with the surrounding text into a single literal rather than a `<>` of
  # constants (`"calc = " <> "14"` → `"calc = 14"`). Only adjacent `{:str, …}` combine; holes stay.
  defp merge_strs(parts) do
    parts
    |> Enum.reduce([], fn
      {:str, b}, [{:str, a} | rest] -> [{:str, a <> b} | rest]
      part, acc -> [part | acc]
    end)
    |> Enum.reverse()
  end

  defp int_type?(t), do: is_binary(t) and Regex.match?(~r/^U?Int\d*$/, t)

  @doc """
  Finish the interpolation bake *after* post-check inlining (ADR-0046 §5).

  The pre-check bake (`resolve_part`/`bake_const`) only sees holes that are already constant. But
  post-check **constant function-call inlining** (`Rian.Optimize`) can turn a hole's value into a
  constant too late for it — `${sq(2, 3)}` resolves to `__prim_int_to_string(sq(2, 3))` pre-check,
  and only after the checker validates the call does `sq(2, 3)` fold to `25`. `rebake/1` re-bakes such
  a now-constant stringify-prim hole (`__prim_int_to_string(25)` → `"25"`) and re-runs `merge_strs`
  inside the interpolation concat, so the program emits the single literal `"sq(2, 3) = 25"` instead
  of `"sq(2, 3) = " <> "25"` — restoring the consistency the phase order accidentally broke.

  **Scoped (boundary A).** It folds ONLY the interpolation prims it itself emits
  (`__prim_int_to_string` / `__prim_char_to_string` over a constant, and `__prim_str_concat_all`'s
  adjacent string literals). It never folds an arbitrary `<>` or a runtime concatenation — Rian
  finishes the interpolation hole it owns; merging two *runtime* strings is the backend's job
  (rustc/LLVM/V8/BEAM-JIT). A `Bool` hole's `if value do "true" else "false" end` is handled by the
  separate dead-`if` simplification once `value` is constant. Idempotent — a second pass is a no-op.
  """
  @rian_sig "pub def rebake(node Expr) Expr"
  @spec rebake(term()) :: term()
  def rebake({:call, {:id, "__prim_int_to_string"}, [arg]}) do
    case rebake(arg) do
      {:num, _} = n ->
        case bake_const(n) do
          {:ok, s} -> {:str, s}
          :no -> {:call, {:id, "__prim_int_to_string"}, [n]}
        end

      other ->
        {:call, {:id, "__prim_int_to_string"}, [other]}
    end
  end

  def rebake({:call, {:id, "__prim_char_to_string"}, [arg]}) do
    case rebake(arg) do
      {:char, _} = c ->
        {:ok, s} = bake_const(c)
        {:str, s}

      other ->
        {:call, {:id, "__prim_char_to_string"}, [other]}
    end
  end

  def rebake({:call, {:id, "__prim_str_concat_all"}, parts}) do
    case parts |> Enum.map(&rebake/1) |> merge_strs() |> Enum.reject(&match?({:str, ""}, &1)) do
      [] -> {:str, ""}
      [only] -> only
      many -> {:call, {:id, "__prim_str_concat_all"}, many}
    end
  end

  def rebake(node) when is_tuple(node),
    do: node |> Tuple.to_list() |> Enum.map(&rebake/1) |> List.to_tuple()

  def rebake(list) when is_list(list), do: Enum.map(list, &rebake/1)
  def rebake(other), do: other
end

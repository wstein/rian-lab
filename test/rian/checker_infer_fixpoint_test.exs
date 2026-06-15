defmodule Rian.CheckerInferFixpointTest do
  # async: false — loads a real module into the VM via :code.load_binary.
  use ExUnit.Case, async: false

  alias Rian.{Beam, Core, Check, Pratt}

  # Self-hosting fixpoint (ADR-0063) for the **type-checker** stage: a Rian-written
  # type inference (examples/rian/selfhost_checker.rian) — a slice of the REAL
  # `Rian.Check.infer/3`, not the toy-language `selfhost_check` checker —
  # compiled to real `.beam`, diffed against `Rian.Check.infer` over a corpus.
  #
  # The reference returns a type string or the atom `:unknown`; the port returns
  # the string `"unknown"` (Rian has no bare atom result here), so the test maps
  # `:unknown -> "unknown"` before comparing.
  #
  # Coverage: ALL 12 Core expression nodes (literals incl. float/char, ids, unary/
  # binary with operand-directed + cross-width arithmetic, prim + higher-order calls,
  # `if`/`case` with flow narrowing, lists, lambdas) under both a typing env (`infer_env/2`,
  # `Check.infer/2`) and the FULL inference context `ic` (`infer_ic/3`, `Check.infer/3`):
  # constructor sum types (`:ctors`), non-generic function returns (`:funs`), GENERIC
  # function-return instantiation (`:fsigs` + type variables — `id(5)` -> `Int53`,
  # `head([1,2,3])` -> `Int53`, `mkpair(1,"a")` -> `Pair(Int53, String)`), and
  # constructor-pattern field narrowing (`:tdefs` — a `case` arm's `Pair(k, v)` binds
  # `k`/`v` to their field types). The port now matches Rian.Check.infer over the whole
  # node + context axis — ADR-0063.

  setup_all do
    {:ok, mod} =
      Beam.load(File.read!("examples/rian/selfhost_checker.rian"), :rian_checker_infer_fixpoint)

    {:ok, mod: mod}
  end

  defp inj(%Core.ENum{text: t}), do: {:c_num, t}
  defp inj(%Core.EStr{value: v}), do: {:c_str, v}
  defp inj(%Core.EChar{value: c}), do: {:c_char, c}
  defp inj(%Core.EId{name: n}), do: {:c_id, n}
  defp inj(%Core.EUnary{op: op, arg: a}), do: {:c_unary, op, inj(a)}
  defp inj(%Core.EBin{op: op, left: l, right: r}), do: {:c_bin, op, inj(l), inj(r)}
  defp inj(%Core.ECall{fun: %Core.EId{name: f}, args: as}), do: {:c_call, f, Enum.map(as, &inj/1)}
  defp inj(%Core.EIf{cond: c, then: t, else: e}), do: {:c_if, inj(c), inj(t), inj(e)}
  defp inj(%Core.EBlock{stmts: stmts}), do: {:c_block, Enum.map(stmts, &inj_stmt/1)}
  defp inj(%Core.ECase{scrut: s, arms: arms}), do: {:c_case, inj(s), Enum.map(arms, &inj_arm/1)}

  defp inj(%Core.EList{elems: elems, tail: tail}),
    do: {:c_list, Enum.map(elems, &inj/1), inj_tail(tail)}

  defp inj(%Core.ELambda{params: ps, body: body}),
    do: {:c_lambda, Enum.map(ps, &inj_param/1), inj(body)}

  defp inj_tail(nil), do: :t_close
  defp inj_tail(:close), do: :t_close
  defp inj_tail(tail), do: {:t_cons, inj(tail)}

  defp inj_param({n, nil}), do: {:lp, n, :pt_none}
  defp inj_param({n, t}), do: {:lp, n, {:pt_some, t}}

  defp inj_stmt({:expr, e}), do: {:s_expr, inj(e)}
  defp inj_stmt({:bind, n, e}), do: {:s_bind, n, inj(e)}

  defp inj_arm({pat, _guard, body}), do: {:c_arm, inj_pat(pat), inj(body)}
  defp inj_pat(%Core.PVar{name: n}), do: {:p_var, n}
  defp inj_pat(%Core.PCtor{ctor: c, args: args}), do: {:p_ctor, c, Enum.map(args, &inj_pat/1)}
  defp inj_pat(_), do: :p_other

  defp ported(mod, src), do: mod.infer(inj(Core.from_expr(Pratt.parse(src))))

  defp reference(src) do
    case Check.infer(Pratt.parse(src)) do
      :unknown -> "unknown"
      ty -> ty
    end
  end

  defp ported_env(mod, src, env), do: mod.infer_env(inj(Core.from_expr(Pratt.parse(src))), env)

  defp reference_env(src, env) do
    case Check.infer(Pratt.parse(src), env) do
      :unknown -> "unknown"
      ty -> ty
    end
  end

  defp ported_ic(mod, src, env, ic),
    do: mod.infer_ic(inj(Core.from_expr(Pratt.parse(src))), env, encode_ic(ic))

  # the port keeps `ic` a `Dict(String,String)`-valued map, so list/struct sub-values
  # are string-encoded (the same projection idea as `inj` for Core): `tdefs` field
  # lists -> ";"-joined, `fsigs` %{params,ret,tvars} -> "params|ret|tvars" (params and
  # tvars comma-joined). `ctors`/`funs` (already String->String) pass through. The
  # reference reads the native shapes; both are built from the same logical @ic.
  defp encode_ic(ic) do
    ic
    |> encode_key(:tdefs, fn fields -> Enum.join(fields, ";") end)
    |> encode_key(:fsigs, fn sig ->
      Enum.join(sig.params, ",") <> "|" <> sig.ret <> "|" <> Enum.join(sig.tvars, ",")
    end)
  end

  defp encode_key(ic, key, f) do
    case Map.get(ic, key) do
      nil -> ic
      sub -> Map.put(ic, key, Map.new(sub, fn {k, v} -> {k, f.(v)} end))
    end
  end

  defp reference_ic(src, env, ic) do
    case Check.infer(Pratt.parse(src), env, ic) do
      :unknown -> "unknown"
      ty -> ty
    end
  end

  @corpus [
    "1",
    "3.14",
    "2.5e3",
    "1.0",
    "'a'",
    "true",
    "false",
    "x",
    "-5",
    "not 1",
    "1 + 2",
    "1 - 2 * 3",
    "1 div 2",
    "1 rem 2",
    "1 / 2",
    "1 < 2",
    "1 <= 2",
    "1 == 2",
    "1 != 2",
    "1 == 2 and 3 < 4",
    "1 < 2 or 3 > 4",
    ~S|"a" <> "b"|,
    "-(1 + 2)",
    "not (1 < 2)",
    # operand-directed arithmetic (arith_type): float arithmetic is Float64 (NOT the
    # old hardcoded Int53), char ordinals widen to Int53, and Int53+Float64 is a
    # mismatch (no implicit int→float) → unknown.
    "1.0 + 2.0",
    "3.14 * 2.0",
    "'a' + 1",
    "'z' - 'a'",
    "1.0 + 2",
    # primitive intrinsics with determinate result types
    "Prim.char_code('a')",
    "Prim.int_to_float(5)",
    ~S|Prim.str_to_atom("x")|,
    "Prim.char_to_string('a')",
    # a general call with no env is conservatively unknown
    "foo(1)",
    # `if` — LUB-join of branches (each a single-expr block). Same-type branches join
    # to that type; an int literal opposite a non-int branch can't adopt it → unknown.
    "if c do 1 else 2 end",
    "if c do true else false end",
    ~S|if c do "a" else "b" end|,
    "if c do 1 else true end",
    # `case` — arm bodies LUB-join; an unbound scrutinee + a var-pattern body is
    # unknown; same-typed arm bodies join to that type; a mismatch is unknown.
    "case n do\n  0 -> 1\n  m -> 2\nend",
    ~S|case n do
  0 -> "a"
  _ -> "b"
end|,
    "case n do\n  0 -> 1\n  _ -> true\nend",
    "case n do\n  0 -> 1\n  m -> m\nend",
    # list literals — elements LUB-join to a concrete `Vec(T)`; empty / mixed → unknown
    "[1, 2, 3]",
    "[]",
    "[1, 2.0]",
    "[1, true]",
    # lambdas — the arrow type `Fn(arg.., body)`; an unannotated param is `_`.
    "(x Int64, y Int64) -> x + y",
    "(x) -> x",
    "(x Int64) -> x",
    ~S|(s String) -> s|,
    "(b Bool) -> not b",
    "(x Int8) -> x + 1"
  ]

  describe "self-hosting checker fixpoint — Rian infer vs Rian.Check.infer" do
    test "the Rian inference agrees with Rian.Check.infer over the slice", %{mod: mod} do
      for src <- @corpus do
        assert ported(mod, src) == reference(src),
               "inference diverged on #{inspect(src)}"
      end
    end
  end

  # a typing env binding variables to types — the headline gap the port now closes.
  # (operand-directed arithmetic widths are a later rung, so bound vars appear in
  # env-lookup / comparison / unary / same-type-Int arithmetic positions.)
  @env %{
    "x" => "Int53",
    "y" => "Int53",
    "s" => "String",
    "b" => "Bool",
    "f" => "Float64",
    "w" => "Int8",
    "u8" => "UInt8",
    "i64" => "Int64",
    "h" => "Int53",
    "t" => "Vec(Int53)",
    "v8" => "Vec(Int8)",
    "v16" => "Vec(Int16)",
    "g" => "Fn(Int64,Int64)",
    "k" => "Fn(Int8,String,Bool)",
    "fu" => "Fn(Int64,_)"
  }
  @env_corpus [
    "x",
    "y",
    "s",
    "b",
    "f",
    "z",
    "-x",
    "-f",
    "not b",
    "x < y",
    "x == y",
    "s <> s",
    "x + y",
    "x - y * x",
    "x + 1",
    # operand-directed widths under the env: an int literal adopts the typed
    # neighbour's width; Float64 arithmetic stays Float64; a mix is unknown.
    "w + 1",
    "w + w",
    "f + f",
    "x + f",
    "f * 2.0",
    # `if` under the env: a literal branch adopts the typed branch's integer type;
    # same-typed branches join to that type.
    "if c do x else 1 end",
    "if c do x else y end",
    ~S|if c do s else "z" end|,
    # cross-width numeric widening in the branch join (Rian.Check.join): same-kind
    # branches widen to the wider width; UInt⊔Int and Int⊔Float climb the lattice.
    "if c do w else x end",
    "if c do x else f end",
    "if c do u8 else i64 end",
    "if c do u8 else x end",
    "if c do w else i64 end",
    # `case` with narrowing: a var pattern binds the scrutinee's type, so the
    # variable's arm body takes that type; arm bodies LUB-join (incl. widening).
    "case x do\n  0 -> 1\n  m -> m\nend",
    "case x do\n  0 -> f\n  m -> m\nend",
    ~S|case s do
  "a" -> s
  v -> v
end|,
    # lists under the env: a cons `[h | t]` joins the head with the tail's element
    # type; element widening applies.
    "[h | t]",
    "[x, y]",
    "[x, f]",
    # parametric covariant join: `Vec(A)`⊔`Vec(B)` = `Vec(A⊔B)` (componentwise widen).
    "if c do v8 else v16 end",
    "if c do v8 else t end",
    "[v8, v16]",
    # calling a function-typed variable (higher-order): the call's type is the
    # function's return type; an `_` (unknown) return reads back as unknown.
    "g(5)",
    ~S|k(1, "x")|,
    "fu(5)",
    "z(5)"
  ]

  describe "self-hosting checker fixpoint — inference under a typing env" do
    test "the Rian inference agrees with Rian.Check.infer over bound variables", %{mod: mod} do
      for src <- @env_corpus do
        assert ported_env(mod, src, @env) == reference_env(src, @env),
               "env inference diverged on #{inspect(src)}"
      end
    end

    test "a bound variable resolves to its env type; an unbound one stays unknown",
         %{mod: mod} do
      assert ported_env(mod, "x", @env) == "Int53"
      assert ported_env(mod, "s", @env) == "String"
      assert ported_env(mod, "z", @env) == "unknown"
      assert reference_env("x", @env) == "Int53"
      assert reference_env("z", @env) == "unknown"
    end
  end

  # an inference context `ic`: constructor names -> their sum type (`:ctors`), and
  # non-generic function names -> their return type (`:funs`). The env still takes
  # precedence over a constructor of the same name.
  @ic %{
    ctors: %{
      "Red" => "Color",
      "Green" => "Color",
      "RGB" => "Color",
      "None" => "Opt",
      "Some" => "Opt"
    },
    funs: %{"area" => "Int64", "name_of" => "String", "mkvec" => "Vec(Int8)"},
    # ctor -> field types (for `case` flow narrowing): RGB carries three ints, Pair a
    # String + an Int64, Some a single generic field `T` (narrows to unknown).
    tdefs: %{
      "RGB" => ["Int64", "Int64", "Int64"],
      "Pair" => ["String", "Int64"],
      "Some" => ["T"],
      "None" => []
    },
    # generic function signatures (forall): instantiate the return from the args.
    fsigs: %{
      "id" => %{params: ["T"], ret: "T", tvars: ["T"]},
      "head" => %{params: ["Vec(T)"], ret: "T", tvars: ["T"]},
      "length" => %{params: ["Vec(T)"], ret: "Int53", tvars: ["T"]},
      "mkpair" => %{params: ["A", "B"], ret: "Pair(A, B)", tvars: ["A", "B"]}
    }
  }
  @ic_corpus [
    # a nullary constructor resolves to its sum type
    {"Red", "Color"},
    {"Green", "Color"},
    # an applied constructor too
    {"RGB(1, 2)", "Color"},
    {"Some(1)", "Opt"},
    # a non-generic named function resolves to its declared return type
    {"area(5)", "Int64"},
    {~S|name_of(1)|, "String"},
    {"mkvec()", "Vec(Int8)"},
    # an unknown name / call is still unknown
    {"Nope", "unknown"},
    {"nope(1)", "unknown"},
    # the env shadows a constructor of the same name
    {"x", "Int53"}
  ]

  describe "self-hosting checker fixpoint — inference under an inference context (ic)" do
    test "constructor + non-generic-function returns agree with Rian.Check.infer/3",
         %{mod: mod} do
      for {src, expected} <- @ic_corpus do
        assert ported_ic(mod, src, @env, @ic) == reference_ic(src, @env, @ic),
               "ic inference diverged on #{inspect(src)}"

        assert ported_ic(mod, src, @env, @ic) == expected,
               "ic inference wrong on #{inspect(src)} — got #{inspect(ported_ic(mod, src, @env, @ic))}, want #{inspect(expected)}"
      end
    end
  end

  # a `case` arm whose pattern is a CONSTRUCTOR binds each field variable to the
  # field's declared type (`ic.tdefs`), so the arm body infers concretely. A generic
  # field (`T`) narrows to `unknown` (conservative — generics not instantiated here).
  @narrow_corpus [
    {"case p do\n  Pair(k, v) -> k\nend", "String"},
    {"case p do\n  Pair(k, v) -> v\nend", "Int64"},
    {"case c do\n  RGB(r, g, b) -> g\nend", "Int64"},
    {"case o do\n  Some(x) -> x\nend", "unknown"},
    {"case o do\n  None -> 1\nend", "Int53"}
  ]

  # a call to a GENERIC function instantiates its return from the argument types: a
  # bare-tvar return is pinned to the arg, a `Vec(T)` param unifies structurally, a
  # return that ignores its tvar is concrete regardless, and an un-pinnable tvar in
  # the return falls back to `unknown` (sound).
  @fsig_corpus [
    {"id(5)", "Int53"},
    {~S|id("x")|, "String"},
    {"head([1, 2, 3])", "Int53"},
    # the return ignores T, so it is concrete even with an un-inferable argument
    {"length([1, 2, 3])", "Int53"},
    {"length(nope)", "Int53"},
    {~S|mkpair(1, "a")|, "Pair(Int53, String)"},
    # an un-pinnable tvar in the return -> unknown (conservative)
    {"id(nope)", "unknown"}
  ]

  describe "self-hosting checker fixpoint — generic-return instantiation (ic.fsigs)" do
    test "generic-function call returns agree with Rian.Check.infer/3", %{mod: mod} do
      for {src, expected} <- @fsig_corpus do
        assert ported_ic(mod, src, @env, @ic) == reference_ic(src, @env, @ic),
               "generic-return instantiation diverged on #{inspect(src)}"

        assert ported_ic(mod, src, @env, @ic) == expected,
               "generic-return wrong on #{inspect(src)} — got #{inspect(ported_ic(mod, src, @env, @ic))}, want #{inspect(expected)}"
      end
    end
  end

  describe "self-hosting checker fixpoint — constructor-pattern field narrowing (ic.tdefs)" do
    test "ctor-pattern field bindings agree with Rian.Check.infer/3", %{mod: mod} do
      for {src, expected} <- @narrow_corpus do
        assert ported_ic(mod, src, @env, @ic) == reference_ic(src, @env, @ic),
               "ctor-narrowing diverged on #{inspect(src)}"

        assert ported_ic(mod, src, @env, @ic) == expected,
               "ctor-narrowing wrong on #{inspect(src)} — got #{inspect(ported_ic(mod, src, @env, @ic))}, want #{inspect(expected)}"
      end
    end
  end

  describe "teeth — the inference is real and conservative" do
    test "an unbound identifier is `unknown` — the checker does not guess", %{mod: mod} do
      assert ported(mod, "x") == "unknown"
      assert reference("x") == "unknown"
    end

    test "a comparison is Bool, not the operands' Int53", %{mod: mod} do
      assert ported(mod, "1 < 2") == "Bool"
      refute ported(mod, "1 < 2") == ported(mod, "1 + 2")
    end

    test "`/` is Float64 even over integer operands (special rule)", %{mod: mod} do
      assert ported(mod, "1 / 2") == "Float64"
      refute ported(mod, "1 / 2") == ported(mod, "1 div 2")
    end

    test "`<>` is String and arithmetic is Int53", %{mod: mod} do
      assert ported(mod, ~S|"a" <> "b"|) == "String"
      assert ported(mod, "1 + 2") == "Int53"
    end
  end

  # === reference-completeness ledger (selfhost_checker vs Rian.Check.infer) ======
  # Each Core node kind the checker infers, with a representative expression and a
  # `ported?` flag, checked with teeth. Coverage is over the node-inference axis;
  # the remaining gap is the non-empty inference context `ic` — generic-return
  # instantiation (`ic.fsigs`) and ctor-pattern field narrowing (`ic.tdefs`) — which
  # is exercised by the `infer_ic` tests above and tracked in ADR-0063, not here.
  defp checker_covers?(mod, src) do
    ported(mod, src) == reference(src)
  rescue
    _ -> false
  catch
    _, _ -> false
  end

  @checker_nodes [
    {"CNum (int)", "1", true},
    {"CNum (float)", "3.14", true},
    {"CStr", ~S|"a"|, true},
    {"CChar", "'a'", true},
    {"CId (bool)", "true", true},
    {"CUnary", "not true", true},
    {"CBin (arith)", "1 + 2", true},
    {"CBin (compare)", "1 < 2", true},
    {"CBin (concat)", ~S|"a" <> "b"|, true},
    {"CCall (prim)", "Prim.char_code('a')", true},
    {"CIf (LUB)", "if true do 1 else 2 end", true},
    {"CCase", "case 1 do\n  0 -> 1\n  m -> m\nend", true},
    {"CList (Vec LUB)", "[1, 2, 3]", true},
    {"CLambda (Fn)", "(x Int64, y Int64) -> x + y", true}
  ]

  describe "type-checker completeness ledger (selfhost_checker vs Rian.Check.infer)" do
    test "every Core node's ported? flag matches reality", %{mod: mod} do
      drift =
        for {name, src, ported?} <- @checker_nodes, checker_covers?(mod, src) != ported? do
          "#{name}: ported?=#{ported?} but selfhost_checker " <>
            "#{if checker_covers?(mod, src), do: "REPRODUCES", else: "does NOT reproduce"} Rian.Check.infer"
        end

      assert drift == [], "checker completeness ledger drifted:\n" <> Enum.join(drift, "\n")
    end

    test "Core-node inference coverage is measured and must not regress" do
      total = length(@checker_nodes)
      ported = Enum.count(@checker_nodes, fn {_, _, p} -> p end)

      IO.puts(
        "\n  selfhost_checker completeness: #{ported}/#{total} Core nodes (ic gap tracked separately)"
      )

      assert ported == total
    end
  end
end

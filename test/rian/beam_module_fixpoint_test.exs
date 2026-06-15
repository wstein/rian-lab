defmodule Rian.BeamModuleFixpointTest do
  # async: false — loads real modules into the VM via :code.load_binary.
  use ExUnit.Case, async: false

  alias Rian.{Beam, Core, Decl, Pratt}

  # Self-hosting fixpoint (ADR-0063) for the **BEAM abstract-forms backend** (whole
  # module): a Rian-written port (examples/rian/selfhost_beam.rian) builds the
  # Erlang abstract forms for a module's functions; this test inflates the port's
  # string-carrying `Form` sum to real forms (the `erl_op`/`var_atom`/`to_snake`
  # conventions), compiles via `:compile.forms`, and RUNS it — asserting it behaves
  # IDENTICALLY to `Rian.Beam` over a corpus + inputs. BEAM uses Erlang's native
  # clause matching, so the port's job is the forms, not test/bind generation.

  setup_all do
    {:ok, mod} =
      Beam.load(File.read!("examples/rian/selfhost_beam.rian"), :rian_beam_module_fixpoint)

    {:ok, mod: mod}
  end

  # ── Core struct -> port Core ──
  defp ic(%Core.ENum{text: t}), do: {:c_num, t}
  defp ic(%Core.EStr{value: s}), do: {:c_str, s}
  defp ic(%Core.EChar{value: cp}), do: {:c_char, cp}
  defp ic(%Core.EId{name: n}), do: {:c_id, n}
  defp ic(%Core.EAtom{name: a}), do: {:c_atom, a}
  defp ic(%Core.EUnary{op: op, arg: a}), do: {:c_unary, op, ic(a)}
  defp ic(%Core.EBin{op: op, left: l, right: r}), do: {:c_bin, op, ic(l), ic(r)}

  defp ic(%Core.ECall{fun: %Core.EId{name: f}, args: args}),
    do: {:c_call, f, Enum.map(args, &ic/1)}

  defp ic(%Core.ETuple{elems: es}), do: {:c_tuple, Enum.map(es, &ic/1)}
  defp ic(%Core.EList{elems: es, tail: :close}), do: {:c_list, Enum.map(es, &ic/1), :t_close}
  defp ic(%Core.EList{elems: es, tail: t}), do: {:c_list, Enum.map(es, &ic/1), {:t_tail, ic(t)}}
  defp ic(%Core.EIf{cond: c, then: t, else: e}), do: {:c_if, ic(c), iblock(t), iblock(e)}
  defp ic(%Core.ECase{scrut: s, arms: arms}), do: {:c_case, ic(s), Enum.map(arms, &iarm/1)}

  defp iarm({p, g, b}), do: {:arm, ip(p), if(g, do: {:g_some, ic(g)}, else: :g_none), iblock(b)}

  defp iblock(%Core.EBlock{stmts: stmts}), do: {:block, Enum.map(stmts, &istmt/1)}
  defp iblock(e), do: {:block, [{:s_expr, ic(e)}]}

  defp istmt({:bind, n, e}), do: {:s_bind, n, ic(e)}
  defp istmt({:typed_bind, n, t, e}), do: {:s_typed_bind, n, t, ic(e)}
  defp istmt({:expr, e}), do: {:s_expr, ic(e)}

  # ── Core pattern -> port Pat ──
  defp ip(%Core.PWild{}), do: :p_wild
  defp ip(%Core.PVar{name: n}), do: {:p_var, n}
  defp ip(%Core.PLit{value: v}) when is_integer(v), do: {:p_int, v}
  defp ip(%Core.PLit{value: v}) when is_binary(v), do: {:p_str, v}
  defp ip(%Core.PChar{value: cp}), do: {:p_char, cp}
  defp ip(%Core.PAtom{name: a}), do: {:p_atom, a}
  defp ip(%Core.PCtor{ctor: c, args: args}), do: {:p_ctor, c, Enum.map(args, &ip/1)}
  defp ip(%Core.PTuple{elems: es}), do: {:p_tuple, Enum.map(es, &ip/1)}
  defp ip(%Core.PList{elems: es, tail: :close}), do: {:p_list, Enum.map(es, &ip/1), :ptl_close}
  defp ip(%Core.PList{elems: es, tail: t}), do: {:p_list, Enum.map(es, &ip/1), {:ptl_tail, ip(t)}}

  defp ifunc(f) do
    clauses =
      Enum.map(f.clauses, fn c ->
        pats = Enum.map(c.pats, fn p -> ip(Core.from_pat(p)) end)
        guard = if c.guard, do: {:g_some, ic(Core.from_expr(Pratt.parse(c.guard)))}, else: :g_none
        body = iblock(Core.from_expr(Pratt.parse_body(c.body)))
        {:clause, pats, guard, body}
      end)

    {:func, f.name, length(hd(f.clauses).pats), clauses}
  end

  defp funcs_of(%{funcs: [], mods: [m]}), do: m.funcs
  defp funcs_of(%{funcs: funcs}), do: funcs

  # ── inflate the port's Form sum -> real Erlang abstract forms (anno 0) ──
  defp inf({:f_int, v}), do: {:integer, 0, v}

  defp inf({:f_str, s}),
    do:
      {:bin, 0, [{:bin_element, 0, {:string, 0, :erlang.binary_to_list(s)}, :default, :default}]}

  defp inf({:f_var, "_"}), do: {:var, 0, :_}
  defp inf({:f_var, n}), do: {:var, 0, var_atom(n)}
  defp inf({:f_atom, a}), do: {:atom, 0, String.to_atom(a)}
  defp inf({:f_ctor_n, c}), do: {:atom, 0, Rian.PatternLower.to_snake(c)}

  defp inf({:f_ctor, c, args}),
    do: {:tuple, 0, [{:atom, 0, Rian.PatternLower.to_snake(c)} | Enum.map(args, &inf/1)]}

  defp inf({:f_op1, op, x}), do: {:op, 0, unary_op(op), inf(x)}
  defp inf({:f_op2, op, l, r}), do: {:op, 0, erl_op(op), inf(l), inf(r)}

  # `<>` is binary construction `<<L/binary, R/binary>>`, not an op (Rian.Beam).
  defp inf({:f_concat, l, r}),
    do:
      {:bin, 0,
       [
         {:bin_element, 0, inf(l), :default, [:binary]},
         {:bin_element, 0, inf(r), :default, [:binary]}
       ]}

  defp inf({:f_call, f, args}),
    do: {:call, 0, {:atom, 0, String.to_atom(f)}, Enum.map(args, &inf/1)}

  defp inf({:f_remote, m, fun, args}),
    do:
      {:call, 0, {:remote, 0, {:atom, 0, String.to_atom(m)}, {:atom, 0, String.to_atom(fun)}},
       Enum.map(args, &inf/1)}

  defp inf({:f_tuple, es}), do: {:tuple, 0, Enum.map(es, &inf/1)}
  defp inf(:f_nil), do: {nil, 0}
  defp inf({:f_cons, h, t}), do: {:cons, 0, inf(h), inf(t)}
  defp inf({:f_match, n, e}), do: {:match, 0, {:var, 0, var_atom(n)}, inf(e)}

  defp inf({:f_if, c, t, e}) do
    {:case, 0, inf(c),
     [
       {:clause, 0, [{:atom, 0, true}], [], Enum.map(t, &inf/1)},
       {:clause, 0, [{:atom, 0, false}], [], Enum.map(e, &inf/1)}
     ]}
  end

  defp inf({:f_case, scrut, clauses}), do: {:case, 0, inf(scrut), Enum.map(clauses, &inf/1)}

  defp inf({:f_clause, pats, guard, body}),
    do: {:clause, 0, Enum.map(pats, &inf/1), inf_guard(guard), Enum.map(body, &inf/1)}

  defp inf({:f_func, name, arity, clauses}),
    do: {:function, 0, String.to_atom(name), arity, Enum.map(clauses, &inf/1)}

  defp inf_guard(:gf_none), do: []
  defp inf_guard({:gf_some, g}), do: [[inf(g)]]

  # Rian.Beam's conventions (replicated so a variant value matches byte-for-byte).
  defp var_atom("_"), do: :_
  defp var_atom("_" <> _ = u), do: String.to_atom(u)
  defp var_atom(<<c::utf8, rest::binary>>), do: String.to_atom(String.upcase(<<c::utf8>>) <> rest)

  defp unary_op("-"), do: :-
  defp unary_op("not"), do: :not

  @erl_op %{
    "==" => :==,
    "!=" => :"/=",
    "<=" => :"=<",
    ">=" => :>=,
    "<" => :<,
    ">" => :>,
    "and" => :andalso,
    "or" => :orelse,
    "+" => :+,
    "-" => :-,
    "*" => :*,
    "/" => :/,
    "div" => :div,
    "rem" => :rem
  }
  defp erl_op(op), do: Map.fetch!(@erl_op, op)

  # build, compile, and load the port's module from `src`.
  defp port_module(mod, src, modname) do
    prog = src |> Decl.parse() |> Rian.Opaque.erase()
    funcs = prog |> funcs_of() |> Enum.reject(&(Map.get(&1, :dispatch) == :dispatcher))
    fn_forms = mod.compile_forms(Enum.map(funcs, &ifunc/1)) |> Enum.map(&inf/1)
    exports = Enum.map(fn_forms, fn {:function, _, n, a, _} -> {n, a} end)

    forms = [{:attribute, 0, :module, modname}, {:attribute, 0, :export, exports} | fn_forms]
    {:ok, ^modname, bin} = :compile.forms(forms, [:return_errors])
    {:module, ^modname} = :code.load_binary(modname, ~c"nofile", bin)
    modname
  end

  # corpus: {source, [{fn_name, arg_list}, …]} — run each input on both modules.
  @corpus [
    {"def add(a Int53, b Int53) Int53 := a + b", [{:add, [2, 3]}, {:add, [10, -4]}]},
    {"def neg(a Int53) Int53 := -a", [{:neg, [7]}]},
    {"def cmp(a Int53, b Int53) Bool := a < b and a != b", [{:cmp, [1, 2]}, {:cmp, [2, 2]}]},
    {"def quot(a Int53, b Int53) Int53 := a div b rem a", [{:quot, [17, 5]}]},
    {"def maxi(a Int53, b Int53) Int53 := if a > b do a else b end",
     [{:maxi, [3, 9]}, {:maxi, [9, 3]}]},
    {"def fib(n Int53) Int53\ndef fib(0) := 0\ndef fib(1) := 1\ndef fib(n) := fib(n - 1) + fib(n - 2)",
     [{:fib, [0]}, {:fib, [1]}, {:fib, [9]}]},
    {"def sign(n Int53) Int53\ndef sign(0) := 0\ndef sign(n) when n > 0 := 1\ndef sign(_) := -1",
     [{:sign, [0]}, {:sign, [5]}, {:sign, [-5]}]},
    # sum variants: construct + dispatch
    {"type Opt := None | Some(Int53)\npub def mk(n Int53) Opt\ndef mk(0) := None\ndef mk(n) := Some(n)",
     [{:mk, [0]}, {:mk, [42]}]},
    {"type Opt := None | Some(Int53)\npub def get(o Opt, d Int53) Int53\ndef get(None, d) := d\ndef get(Some(v), _) := v",
     [{:get, [:none, 99]}, {:get, [{:some, 7}, 99]}]},
    # tuple construct + dispatch (Result / case)
    {"def chk(x Int53) Int53 := case {:ok, x} do\n  {:ok, v} -> v\n  _ -> 0\nend", [{:chk, [5]}]},
    # list construct + cons dispatch
    {"def hd(xs Vec(Int53), d Int53) Int53\ndef hd([], d) := d\ndef hd([h | t], _) := h",
     [{:hd, [[], 0]}, {:hd, [[3, 4, 5], 0]}]},
    {"def cons(x Int53, xs Vec(Int53)) Vec(Int53) := [x | xs]", [{:cons, [1, [2, 3]]}]},
    # String / Char literals — return bodies, char guard, char- and string-clause heads
    {"def tag() String := \"ok\"", [{:tag, []}]},
    {"def kind(c Char) Int64\ndef kind('+') := 1\ndef kind('-') := 2\ndef kind(_) := 0",
     [{:kind, [?+]}, {:kind, [?-]}, {:kind, [?x]}]},
    {"def sel(s String) Int64\ndef sel(\"a\") := 1\ndef sel(_) := 0",
     [{:sel, ["a"]}, {:sel, ["z"]}]},
    # Prim.* — the portable string/char intrinsics the lexer leans on (str_chars →
    # String.to_charlist, str_from_chars → List.to_string, char_code → identity)
    {"def echo(s String) String := Prim.str_from_chars(Prim.str_chars(s))",
     [{:echo, ["hi"]}, {:echo, ["ok"]}]},
    {"def d(c Char) Int64 := Prim.char_code(c) - Prim.char_code('0')", [{:d, [?7]}, {:d, [?0]}]},
    # `<>` and the explicit `Prim.str_concat` (selfhost_decl uses the latter)
    {"def cat(a String, b String) String := a <> b", [{:cat, ["foo", "bar"]}, {:cat, ["", "x"]}]},
    {"def pc(a String, b String) String := Prim.str_concat(a, b)", [{:pc, ["x", "y"]}]},
    {"def wrap(s String) String := \"[\" <> s <> \"]\"", [{:wrap, ["hi"]}]}
  ]

  describe "self-hosting BEAM-module fixpoint — Rian forms run identically to Rian.Beam" do
    test "the port's compiled module behaves exactly like Rian.Beam's", %{mod: mod} do
      for {src, calls} <- @corpus do
        {:ok, ref, refbin} = Beam.compile(src, :"rbm_ref_#{System.unique_integer([:positive])}")
        {:module, ^ref} = :code.load_binary(ref, ~c"nofile", refbin)
        port = port_module(mod, src, :"rbm_port_#{System.unique_integer([:positive])}")

        for {fname, args} <- calls do
          assert apply(ref, fname, args) == apply(port, fname, args),
                 "diverged: #{fname}(#{inspect(args)}) on\n#{src}"
        end
      end
    end
  end

  describe "teeth — the forms are real abstract forms that compile + dispatch" do
    test "a multi-clause function dispatches by native pattern (no explicit tests)", %{mod: mod} do
      src =
        "def fib(n Int53) Int53\ndef fib(0) := 0\ndef fib(1) := 1\ndef fib(n) := fib(n - 1) + fib(n - 2)"

      port = port_module(mod, src, :rbm_teeth_fib)
      assert port.fib(10) == 55
    end

    test "the port emits a Form, not Erlang atoms directly (Rian can't spell `:+`)", %{mod: mod} do
      [{:f_func, "f", 1, [{:f_clause, _, _, [body]}]}] =
        mod.compile_forms([
          {:func, "f", 1,
           [
             {:clause, [{:p_var, "a"}], :g_none,
              {:block, [{:s_expr, {:c_bin, "+", {:c_id, "a"}, {:c_id, "a"}}}]}}
           ]}
        ])

      # the operator rides as the STRING "+", inflated to the atom by this test
      assert {:f_op2, "+", _, _} = body
    end
  end
end

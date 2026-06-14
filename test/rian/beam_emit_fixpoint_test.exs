defmodule Rian.BeamEmitFixpointTest do
  # async: false — loads a real module into the VM via :code.load_binary.
  use ExUnit.Case, async: false

  alias Rian.{Beam, Core, Pratt}

  # Self-hosting fixpoint (ADR-0063) for the **BEAM abstract-forms backend** (the
  # default self-host target): a Rian-written forms emitter
  # (examples/rian/selfhost_beam.rian), compiled to real `.beam`, diffed against
  # Erlang's OWN parser. The port builds an abstract form for an expression; the
  # test inflates its string operators to atoms (Rian can't spell `:+`/`:"=<"`)
  # and asserts the result equals `:erl_parse`'s canonical AST for the equivalent
  # Erlang expression, term-for-term (annotations normalised to 0).
  #
  # This pins the port to Erlang's actual abstract-form grammar — exactly the
  # contract `Rian.Beam` must satisfy to feed `:compile.forms`.
  #
  # Slice: integer/atom/identifier leaves, prefix unary, binary operators.
  # Strings, calls, lists, `case`, and prims are the `:partial` tail (ADR-0063).

  setup_all do
    {:ok, mod} = Beam.load(File.read!("examples/rian/selfhost_beam.rian"), :rian_beam_fixpoint)
    {:ok, mod: mod}
  end

  defp inj(%Core.ENum{text: t}), do: {:c_num, t}
  defp inj(%Core.EId{name: n}), do: {:c_id, n}
  defp inj(%Core.EAtom{name: a}), do: {:c_atom, a}
  defp inj(%Core.EUnary{op: op, arg: a}), do: {:c_unary, op, inj(a)}
  defp inj(%Core.EBin{op: op, left: l, right: r}), do: {:c_bin, op, inj(l), inj(r)}
  defp inj(%Core.ECall{fun: %Core.EId{name: f}, args: as}), do: {:c_call, f, Enum.map(as, &inj/1)}

  # the port's string-operator Form sum -> real Erlang abstract forms (anno 0).
  defp to_form({:f_int, t}), do: {:integer, 0, String.to_integer(t)}
  defp to_form({:f_var, n}), do: {:var, 0, var_atom(n)}
  defp to_form({:f_atom, a}), do: {:atom, 0, String.to_atom(a)}
  defp to_form({:f_un, op, x}), do: {:op, 0, String.to_atom(op), to_form(x)}
  defp to_form({:f_bin, op, l, r}), do: {:op, 0, String.to_atom(op), to_form(l), to_form(r)}

  # a local call form: the callee name (a string) inflates to an `{atom, _, f}`
  # head, the args recurse — `{call, 0, {atom, 0, f}, [arg forms]}`.
  defp to_form({:f_call, f, args}),
    do: {:call, 0, {:atom, 0, String.to_atom(f)}, Enum.map(args, &to_form/1)}

  # Rian.Beam's variable naming: capitalise the first letter (so `a` -> `A`).
  defp var_atom(<<c, rest::binary>>), do: String.to_atom(String.upcase(<<c>>) <> rest)

  defp ported(mod, src), do: to_form(mod.emit(inj(Core.from_expr(Pratt.parse(src)))))

  # the canonical Erlang abstract form for an expression, annotations zeroed.
  defp erl(src) do
    {:ok, toks, _} = :erl_scan.string(String.to_charlist(src <> "."))
    {:ok, [form]} = :erl_parse.parse_exprs(toks)
    zero_anno(form)
  end

  defp zero_anno(t) when is_tuple(t) do
    [tag | rest] = Tuple.to_list(t)

    rest =
      rest |> Enum.with_index() |> Enum.map(fn {e, i} -> if i == 0, do: 0, else: zero_anno(e) end)

    List.to_tuple([tag | rest])
  end

  defp zero_anno(l) when is_list(l), do: Enum.map(l, &zero_anno/1)
  defp zero_anno(x), do: x

  # {Rian expression, the equivalent Erlang expression}
  @corpus [
    {"42", "42"},
    {"a", "A"},
    {":ok", "ok"},
    {"-a", "- A"},
    {"not a", "not A"},
    {"a + b * c", "A + B * C"},
    {"a * b + c", "A * B + C"},
    {"a - b - c", "A - B - C"},
    {"a div b rem c", "A div B rem C"},
    {"a == b", "A == B"},
    {"a != b", "A /= B"},
    {"a <= b", "A =< B"},
    {"a >= b", "A >= B"},
    {"a < b", "A < B"},
    {"not a and b or c", "not A andalso B orelse C"},
    {"a or b and c", "A orelse B andalso C"},
    # local function calls -> {call, _, {atom, _, f}, Args}: zero/one/many args,
    # a binary argument, and a nested call (args recurse)
    {"f()", "f()"},
    {"g(a)", "g(A)"},
    {"g(a, b)", "g(A, B)"},
    {"g(a + b)", "g(A + B)"},
    {"g(f(a), b)", "g(f(A), B)"}
  ]

  describe "self-hosting BEAM-backend fixpoint — Rian forms vs :erl_parse" do
    test "the Rian-built abstract forms equal Erlang's canonical AST", %{mod: mod} do
      for {rian, erlang} <- @corpus do
        assert ported(mod, rian) == erl(erlang),
               "abstract forms diverged on #{inspect(rian)}"
      end
    end

    test "the forms actually compile and run via :compile.forms", %{mod: mod} do
      # wrap `f(A, B, C) -> <form>.` and run it — the forms must be loadable.
      form = ported(mod, "a + b * c")

      fn_form =
        {:function, 0, :f, 3,
         [{:clause, 0, [{:var, 0, :A}, {:var, 0, :B}, {:var, 0, :C}], [], [form]}]}

      mod_forms = [
        {:attribute, 0, :module, :rian_beam_emit_run},
        {:attribute, 0, :export, [{:f, 3}]},
        fn_form
      ]

      {:ok, m, bin} = :compile.forms(mod_forms, [:return_errors])
      {:module, ^m} = :code.load_binary(m, ~c"nofile", bin)
      assert m.f(2, 3, 4) == 2 + 3 * 4
    end
  end

  describe "teeth — the operator mapping and structure are real" do
    test "Rian operators are mapped to Erlang spellings (==→==, !=→/=, <=→=<)", %{mod: mod} do
      assert ported(mod, "a != b") == {:op, 0, :"/=", {:var, 0, :A}, {:var, 0, :B}}
      assert ported(mod, "a <= b") == {:op, 0, :"=<", {:var, 0, :A}, {:var, 0, :B}}
      assert ported(mod, "a and b") == {:op, 0, :andalso, {:var, 0, :A}, {:var, 0, :B}}
      # the Rian spelling must NOT survive into the forms.
      refute match?({:op, 0, :!=, _, _}, ported(mod, "a != b"))
    end

    test "precedence/structure is preserved and discriminates", %{mod: mod} do
      refute ported(mod, "a + b * c") == ported(mod, "(a + b) * c")
      refute ported(mod, "a - b") == ported(mod, "b - a")
    end

    test "a local call is a `{call, _, {atom, _, f}, args}` form, args recurse", %{mod: mod} do
      assert ported(mod, "g(a, b)") ==
               {:call, 0, {:atom, 0, :g}, [{:var, 0, :A}, {:var, 0, :B}]}

      # the callee is an atom head (not a var), and arg order is preserved
      assert {:call, 0, {:atom, 0, :g}, _} = ported(mod, "g(a)")
      refute ported(mod, "g(a, b)") == ported(mod, "g(b, a)")
    end
  end
end

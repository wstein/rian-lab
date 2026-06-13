defmodule Rian.MacroTest do
  use ExUnit.Case, async: false
  alias Rian.{Pratt, Macro, Comptime, Lower}

  @env Macro.build_env([
         %{name: "unless", params: ["cond", "body"], template: "if not cond do body else 0 end"},
         %{name: "square", params: ["x"], template: "x * x"},
         %{name: "add_tmp", params: ["x"], template: "if true do tmp := 100; x + tmp else 0 end"}
       ])

  defp pipe(src), do: Pratt.parse(src) |> (&Macro.expand(@env, &1)).() |> Comptime.fold()
  defp el(src), do: Lower.emit_ast(pipe(src), :elixir)
  defp rs(src), do: Lower.emit_ast(pipe(src), :rust)

  setup_all do
    defs =
      [
        {"t", "n", "unless(n > 5, n * 10)"},
        {"sq", "m", "square(m + 1)"},
        {"hyg", "tmp", "add_tmp(tmp)"},
        {"c", "_x", "comptime(2 + 3 * 4)"}
      ]
      |> Enum.map_join("\n", fn {name, p, body} -> "def #{name}(#{p}) do #{el(body)} end" end)

    Code.eval_string("defmodule MacT do\n#{defs}\nend")
    :ok
  end

  describe "declarative pattern->template expansion" do
    test "unless expands to an if/not" do
      assert el("unless(n > 5, n * 10)") == "if not (n > 5) do n * 10 else 0 end"
      assert rs("unless(n > 5, n * 10)") == "if !(n > 5) { n * 10 } else { 0 }"
    end

    test "AST substitution avoids the C-preprocessor precedence bug" do
      # SQ(a+b) in C => a+b*a+b; here it must be (a + b) * (a + b)
      assert el("square(a + b)") == "(a + b) * (a + b)"
      assert rs("square(a + b)") == "(a + b) * (a + b)"
    end
  end

  describe "hygiene" do
    test "macro-local binder is gensym-renamed, caller's variable is untouched" do
      out = el("add_tmp(tmp)")
      assert out =~ ~r/tmp__h\d+ = 100/
      assert out =~ ~r/tmp \+ tmp__h\d+/
      refute out =~ "tmp = 100; tmp + tmp"
    end

    test "hygiene gives the correct runtime value (105, not 200)" do
      assert MacT.hyg(5) == 105
    end
  end

  describe "comptime (Zig-style) folding" do
    test "folds a constant expression to a literal" do
      assert el("comptime(2 + 3 * 4)") == "14"
      assert el("comptime((1 + 2) * 5)") == "15"
      assert rs("comptime(2 + 3 * 4)") == "14"
    end

    test "folds a boolean comparison" do
      assert el("comptime(3 > 5)") == "false"
      assert el("comptime(10 == 10)") == "true"
    end

    test "folds float constants (`/` is float division)" do
      assert el("comptime(3.14 * 2)") == "6.28"
      assert el("comptime(1 / 2)") == "0.5"
      assert rs("comptime(1 / 2)") == "0.5"
    end

    test "`div`/`rem` refuse float operands (integers only)" do
      assert_raise RuntimeError, ~r/require integer operands/, fn ->
        pipe("comptime(3.0 div 2)")
      end
    end
  end

  describe "comptime sandbox (ADR-0009)" do
    test "refuses function calls" do
      assert_raise RuntimeError, ~r/calls are not allowed/, fn -> pipe("comptime(foo(3))") end
    end

    test "refuses non-constants" do
      assert_raise RuntimeError, ~r/not a compile-time constant/, fn ->
        pipe("comptime(x + 1)")
      end
    end

    test "refuses FFI" do
      assert_raise RuntimeError, ~r/not allowed/, fn -> pipe("comptime(:lists.sum(xs))") end
    end
  end

  describe "executes on the BEAM" do
    test "macro-expanded functions run correctly" do
      assert MacT.t(3) == 30
      assert MacT.t(7) == 0
      assert MacT.sq(4) == 25
      assert MacT.c(0) == 14
    end
  end

  describe "portable-core discipline (ADR-0035/0058)" do
    @penv Macro.build_env(
            [
              {"unwrap", "e", "with {:ok, v} <- e do v end"},
              {"square", "x", "x * x"}
            ]
            |> Enum.map(fn {n, p, t} -> %{name: n, params: [p], template: t} end)
          )

    test "rejects a macro whose template introduces a failable bind (`with … <-`)" do
      assert_raise RuntimeError, ~r/introduces a failable bind/, fn ->
        Macro.expand(@penv, Pratt.parse("unwrap(f(a))"), portable: true)
      end
    end

    test "the same expansion is allowed when not portable (default)" do
      assert Macro.expand(@penv, Pratt.parse("unwrap(f(a))")) ==
               Macro.expand(@penv, Pratt.parse("unwrap(f(a))"), portable: false)

      refute match?(nil, Macro.expand(@penv, Pratt.parse("unwrap(f(a))")))
    end

    test "a control-flow-free macro is fine in portable mode" do
      assert el("square(m + 1)") == "(m + 1) * (m + 1)"
      refute match?(nil, Macro.expand(@penv, Pratt.parse("square(m + 1)"), portable: true))
    end
  end

  # Each template below carries a block binder `t` (so freshen has a binder to
  # rename), placed inside the node kind under test. After expansion `t` must be
  # gensym-renamed (`t__h<n>`) consistently everywhere it occurs, while the
  # caller's identifiers and macro params are untouched.
  defp expand1(name, params, template, call) do
    env = Macro.build_env([%{name: name, params: params, template: template}])
    Macro.expand(env, Pratt.parse(call))
  end

  describe "hygiene over every AST node kind (collect_binders/rename, ADR-0030)" do
    test "lambda: param + body are renamed (collect_binders/rename lambda)" do
      out = expand1("m", ["x"], "(u) -> u + t", "m(99)")
      # The only template-local binder is the lambda param `u`, which must be
      # renamed in both the param list and the body; free `t` stays free.
      assert {:lambda, [{u, nil}], {:bin, "+", {:id, u}, {:id, "t"}}} = out
      assert u =~ ~r/^u__h\d+$/
    end

    test "call: function position + every argument are walked and renamed" do
      out = expand1("m", ["x"], "if true do t := 1; g(t, t + 2) else 0 end", "m(99)")

      assert {:if, _, {:block, [{:bind, t, _}, {:expr, callnode}]}, _} = out
      assert t =~ ~r/^t__h\d+$/

      assert {:call, {:id, "g"}, [{:id, ^t}, {:bin, "+", {:id, ^t}, {:num, "2"}}]} =
               callnode
    end

    test "dot: object position is renamed, field name preserved" do
      out = expand1("m", ["x"], "if true do t := 1; t.fld else 0 end", "m(99)")
      assert {:if, _, {:block, [{:bind, t, _}, {:expr, {:dot, {:id, t}, "fld"}}]}, _} = out
      assert t =~ ~r/^t__h\d+$/
    end

    test "capture: anonymous `&(...)` body is walked and renamed" do
      out = expand1("m", ["x"], "if true do t := 1; &(t + 1) else 0 end", "m(99)")

      assert {:if, _, {:block, [{:bind, t, _}, {:expr, cap}]}, _} = out
      assert {:capture, {:bin, "+", {:id, ^t}, {:num, "1"}}} = cap
      assert t =~ ~r/^t__h\d+$/
    end

    test "capture_named: path is walked (arity preserved)" do
      out = expand1("m", ["x"], "if true do t := 1; &t/2 else 0 end", "m(99)")

      assert {:if, _, {:block, [{:bind, t, _}, {:expr, cap}]}, _} = out
      assert {:capture_named, {:id, ^t}, 2} = cap
      assert t =~ ~r/^t__h\d+$/
    end

    test "case: scrutinee, guard and arm body are all renamed" do
      out =
        expand1(
          "m",
          ["x"],
          "if true do t := 1; case t do y when y -> t end else 0 end",
          "m(99)"
        )

      assert {:if, _, {:block, [{:bind, t, _}, {:expr, casenode}]}, _} = out
      assert t =~ ~r/^t__h\d+$/
      # scrutinee + arm body renamed; guard expr is walked (here a pattern var
      # `y`, not a collected binder, so left as-is).
      assert {:case, {:id, ^t}, [{{:var, "y"}, {:id, "y"}, {:id, ^t}}]} = casenode
    end

    test "case: guard = nil branch is handled (g && rename(g) short-circuits)" do
      out =
        expand1("m", ["x"], "if true do t := 1; case t do y -> t end else 0 end", "m(99)")

      assert {:if, _, {:block, [{:bind, _t, _}, {:expr, casenode}]}, _} = out
      assert {:case, {:id, t}, [{{:var, "y"}, nil, {:id, t}}]} = casenode
      assert t =~ ~r/^t__h\d+$/
    end

    test "list_lit with cons tail: elements + tail renamed" do
      out =
        expand1("m", ["x"], "if true do t := 1; [t, t + 2 | t] else 0 end", "m(99)")

      assert {:if, _, {:block, [{:bind, t, _}, {:expr, list}]}, _} = out
      assert t =~ ~r/^t__h\d+$/

      assert {:list_lit, [{:id, ^t}, {:bin, "+", {:id, ^t}, {:num, "2"}}], {:tail, {:id, ^t}}} =
               list
    end

    test "list_lit without tail: nil-tail branch is handled" do
      out = expand1("m", ["x"], "if true do t := 1; [t, t] else 0 end", "m(99)")
      assert {:if, _, {:block, [{:bind, t, _}, {:expr, list}]}, _} = out
      assert {:list_lit, [{:id, ^t}, {:id, ^t}], nil} = list
      assert t =~ ~r/^t__h\d+$/
    end

    test "map_lit: every value is walked and renamed, keys preserved" do
      out =
        expand1("m", ["x"], "if true do t := 1; %{a: t, b: t + 1} else 0 end", "m(99)")

      assert {:if, _, {:block, [{:bind, t, _}, {:expr, mapnode}]}, _} = out
      assert t =~ ~r/^t__h\d+$/

      assert {:map_lit, [{"a", {:id, ^t}}, {"b", {:bin, "+", {:id, ^t}, {:num, "1"}}}]} =
               mapnode
    end
  end

  describe "@max_depth runaway backstop (ADR-0030)" do
    test "a self-referential macro raises \"macro expansion too deep\"" do
      env = Macro.build_env([%{name: "loopy", params: ["x"], template: "loopy(x)"}])

      assert_raise RuntimeError, ~r/macro expansion too deep/, fn ->
        Macro.expand(env, Pratt.parse("loopy(1)"))
      end
    end
  end
end

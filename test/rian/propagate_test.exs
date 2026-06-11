defmodule Rian.PropagateTest do
  # async: false — the execution tests define modules via Code.eval_string.
  use ExUnit.Case, async: false

  alias Rian.{Capability, Lower, Pratt}

  defp run_fn(body) do
    %{
      name: "run",
      param_name: "x",
      param_type: "i64",
      param_cap: :val,
      ret: "i64",
      clauses: [%{pats: [{:var, "x"}], body: body}]
    }
  end

  defp last_line(s), do: s |> String.split("\n") |> List.last()

  describe "parsing & lowering" do
    test "postfix `?` builds a {:try} node" do
      assert Pratt.parse_sexpr("g(x)?") == "(? (call g x))"
    end

    test "Rust lowers to idiomatic postfix `?`" do
      assert Lower.emit_expr("g(x)?", :rust) == "g(x)?"
      assert Lower.emit_expr("a? + b?", :rust) == "a? + b?"
    end

    test "Elixir lowers to Rian.Q.unwrap/1" do
      assert Lower.emit_expr("g(x)?", :elixir) == "Rian.Q.unwrap(g(x))"
    end
  end

  describe "function-body wrapping" do
    test "a body using `?` is wrapped in a propagation try/catch" do
      el = Lower.compile_beam([], run_fn("step(x)?")).elixir
      assert el =~ "try do"
      assert el =~ "catch {:__rian_q__, rian_v} -> rian_v end"
    end

    test "a body NOT using `?` is left unwrapped" do
      refute Lower.compile_beam([], run_fn("x + 1")).elixir =~ "try do"
    end
  end

  describe "executes on the BEAM" do
    test "Result: ok unwraps, error short-circuits" do
      el = Lower.compile_beam([], run_fn("step(x)?")).elixir |> last_line()

      Code.eval_string("""
      defmodule RPropResult do
        def step(x) when x > 0, do: {:ok, x * 10}
        def step(_), do: {:error, :neg}
        #{el}
      end
      """)

      assert RPropResult.run(3) == 30
      assert RPropResult.run(-1) == {:error, :neg}
    end

    test "Option: some unwraps, none short-circuits" do
      el = Lower.compile_beam([], run_fn("opt(x)?")).elixir |> last_line()

      Code.eval_string("""
      defmodule RPropOption do
        def opt(x) when x > 0, do: {:some, x}
        def opt(_), do: :none
        #{el}
      end
      """)

      assert RPropOption.run(5) == 5
      assert RPropOption.run(0) == :none
    end
  end

  describe "linearity sees through `?`" do
    test "an iso used once under `?` is ok; reused alongside it is rejected" do
      assert Capability.lin_check(%{"s" => :iso}, Pratt.parse("step(s)?")) == :ok

      assert Capability.lin_check(%{"s" => :iso}, Pratt.parse("pair(step(s)?, s)")) ==
               {:error, [{"s", 2}]}
    end
  end

  describe "Rian.Q.unwrap/1" do
    test "unwraps ok/some, throws to propagate otherwise" do
      assert Rian.Q.unwrap({:ok, 1}) == 1
      assert Rian.Q.unwrap({:some, 2}) == 2
      assert catch_throw(Rian.Q.unwrap({:error, :x})) == {:__rian_q__, {:error, :x}}
      assert catch_throw(Rian.Q.unwrap(:none)) == {:__rian_q__, :none}
    end
  end
end

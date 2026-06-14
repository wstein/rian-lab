defmodule Rian.PropagationTest do
  # async: false — loads real modules into the VM via :code.load_binary.
  use ExUnit.Case, async: false

  alias Rian.{Beam, Pratt}

  # ADR-0066 (P4): a bare `name <- expr` statement is error propagation — `{:ok, v}`
  # binds and continues; `{:error, e}` short-circuits, returning the error
  # unchanged. Sugar over the `Result` `case` that `with` desugars to.

  describe "the `<-` statement desugars to a Result case (ADR-0066)" do
    test "a block with `<-` becomes a case: ok continues, error short-circuits" do
      ast = Pratt.parse_body("x <- f(a) ; {:ok, x}")

      # ok arm binds x and continues; error arm returns {:error, __prop_e}
      assert {:block, [{:expr, {:case, {:call, {:id, "f"}, _}, arms}}]} = ast
      assert [{ok_pat, nil, _ok_body}, {err_pat, nil, err_body}] = arms
      assert ok_pat == {:tuple, [{:atom, "ok"}, {:var, "x"}]}
      assert err_pat == {:tuple, [{:atom, "error"}, {:var, "__prop_e"}]}
      assert err_body == {:tuple, [{:atom, "error"}, {:id, "__prop_e"}]}
    end

    test "a plain block (no `<-`) is unchanged" do
      assert {:block, [{:bind, "x", _}, {:expr, {:id, "x"}}]} = Pratt.parse_body("x := 1 ; x")
    end
  end

  describe "`<-` propagation runs on the BEAM" do
    setup do
      {:ok, mod} =
        Beam.load(
          """
          def safe_div(a Int64, b Int64) Symbol := if b == 0 do {:error, :divzero} else {:ok, a div b} end
          def calc(a Int64, b Int64, c Int64) Symbol
            x <- safe_div(a, b)
            y <- safe_div(x, c)
            {:ok, y}
          end
          """,
          :rian_propagation
        )

      {:ok, mod: mod}
    end

    test "both binds succeed -> the final value", %{mod: mod} do
      assert mod.calc(100, 5, 2) == {:ok, 10}
    end

    test "the first `<-` fails -> its error propagates, skipping the rest", %{mod: mod} do
      assert mod.calc(100, 0, 2) == {:error, :divzero}
    end

    test "a later `<-` fails -> its error propagates", %{mod: mod} do
      assert mod.calc(100, 5, 0) == {:error, :divzero}
    end
  end

  describe "a trailing `<-` is a compile error (ADR-0066: it binds and continues)" do
    # Regression: a `<-` with nothing after it used to compile and silently return
    # `nil` on the ok branch (while the error branch returned `{:error, e}`). It is
    # meaningless — reject it instead of mis-running.
    test "a `<-` as the last statement of a block is rejected" do
      assert_raise ArgumentError, ~r/must be followed by an expression/, fn ->
        Pratt.parse_body("x <- f(a)")
      end
    end

    test "a `<-` after earlier statements but still last is rejected" do
      assert_raise ArgumentError, ~r/must be followed by an expression/, fn ->
        Pratt.parse_body("y := 1 ; x <- f(a)")
      end
    end
  end
end

defmodule Rian.CapabilityTest do
  use ExUnit.Case, async: true
  alias Rian.Capability, as: C
  alias Rian.Lower
  alias Rian.Pratt

  describe "Rust parameter-type matrix" do
    test "val borrows (idiomatic &str / &[T] / &T), Copy passes by value" do
      assert C.rust_param(:val, "i64") == "i64"
      assert C.rust_param(:val, "f64") == "f64"
      assert C.rust_param(:val, "str") == "&str"
      assert C.rust_param(:val, "Vec(f64)") == "&[f64]"
      assert C.rust_param(:val, "Shape") == "&Shape"
    end

    test "iso owns / moves" do
      assert C.rust_param(:iso, "str") == "String"
      assert C.rust_param(:iso, "Vec(f64)") == "Vec<f64>"
      assert C.rust_param(:iso, "Shape") == "Shape"
      assert C.rust_param(:iso, "i64") == "i64"
    end

    test "ref is &mut over the owned form" do
      assert C.rust_param(:ref, "i64") == "&mut i64"
      assert C.rust_param(:ref, "str") == "&mut String"
      assert C.rust_param(:ref, "Vec(f64)") == "&mut Vec<f64>"
    end

    test "copy? classifies primitives" do
      assert C.copy?("i64")
      assert C.copy?("f64")
      assert C.copy?("bool")
      refute C.copy?("str")
      refute C.copy?("Shape")
    end
  end

  describe "BEAM linearity (use-once)" do
    test "iso used once is fine" do
      assert C.lin_check(%{"f" => :iso}, Pratt.parse("use(f)")) == :ok
    end

    test "iso used twice is an error naming the binding and count" do
      assert C.lin_check(%{"f" => :iso}, Pratt.parse("pair(f, f)")) == {:error, [{"f", 2}]}
    end

    test "ref used twice is an error" do
      assert C.lin_check(%{"x" => :ref}, Pratt.parse("g(x) + h(x)")) == {:error, [{"x", 2}]}
    end

    test "val may be used many times (this is why r * r is allowed)" do
      assert C.lin_check(%{"r" => :val}, Pratt.parse("pi * r * r")) == :ok
    end

    test "block: consuming an iso once across bindings is fine" do
      assert C.lin_check_block(
               %{"f" => :iso},
               [{"b", :val, Pratt.parse("read(f)")}],
               Pratt.parse("b")
             ) ==
               :ok
    end

    test "block: consuming an iso twice is an error" do
      assert C.lin_check_block(
               %{"f" => :iso},
               [{"x", :val, Pratt.parse("read(f)")}, {"y", :val, Pratt.parse("read(f)")}],
               Pratt.parse("0")
             ) == {:error, [{"f", 2}]}
    end
  end

  # Regression: count_uses must be total over every node the parser emits.
  # Before this, dot/lambda/if/list/map nodes raised FunctionClauseError, so the
  # linearity check crashed on exactly the self-hosting expressions (ADR-0028/0029).
  describe "BEAM linearity over self-hosting expressions" do
    test "dot access counts the head, not the field name" do
      assert C.lin_check(%{"f" => :iso}, Pratt.parse("f.x")) == :ok
      assert C.lin_check(%{"f" => :iso}, Pratt.parse("g(f.x, f.y)")) == {:error, [{"f", 2}]}
    end

    test "if is branch-aware: an iso moved once per arm is consumed once" do
      assert C.lin_check(%{"f" => :iso}, Pratt.parse("if c do use(f) else drop(f) end")) == :ok
    end

    test "if still flags an iso used twice within a single arm" do
      assert C.lin_check(%{"f" => :iso}, Pratt.parse("if c do pair(f, f) else 0 end")) ==
               {:error, [{"f", 2}]}
    end

    test "lambda parameters shadow the linear environment" do
      assert C.lin_check(%{"x" => :iso}, Pratt.parse("(x) -> pair(x, x)")) == :ok
    end

    test "a lambda still counts an outer iso captured in its body" do
      assert C.lin_check(%{"f" => :iso}, Pratt.parse("(x) -> pair(f, f)")) ==
               {:error, [{"f", 2}]}
    end

    test "block bindings shadow the name for later statements" do
      assert C.lin_check(%{"f" => :iso}, Pratt.parse("if true do f := 0; pair(f, f) else 0 end")) ==
               :ok
    end

    test "list literals count their elements" do
      assert C.lin_check(%{"f" => :iso}, Pratt.parse("[f, f]")) == {:error, [{"f", 2}]}
    end

    test "map literals count their values" do
      assert C.lin_check(%{"f" => :iso}, Pratt.parse("%{a: f, b: f}")) == {:error, [{"f", 2}]}
    end
  end

  describe "BEAM legality" do
    test "ref is rejected on the BEAM target" do
      assert_raise RuntimeError, ~r/`ref` is not permitted on the BEAM/, fn ->
        C.beam_legal!(:ref)
      end
    end

    test "val / iso / tag are legal on the BEAM target" do
      assert C.beam_legal!(:val) == :ok
      assert C.beam_legal!(:iso) == :ok
      assert C.beam_legal!(:tag) == :ok
    end
  end

  describe "capability drives the emitted Rust signature" do
    defp types do
      [%{name: "Shape", variants: [%{ctor: "Circle", fields: [%{label: "radius", type: "f64"}]}]}]
    end

    defp area(cap) do
      %{
        name: "area",
        param_name: "shape",
        param_type: "Shape",
        param_cap: cap,
        ret: "f64",
        clauses: [%{pats: [{:ctor, "Circle", [{:var, "r"}]}], body: "pi * r * r"}]
      }
    end

    test "val Shape -> &Shape" do
      assert Lower.to_rust(area(:val), types(), %{
               circle: %{enum: "Shape", ctor: "Circle", labels: ["radius"], named: true}
             }) =~
               "fn area(shape: &Shape) -> f64"
    end

    test "iso Shape -> Shape (owned)" do
      assert Lower.to_rust(area(:iso), types(), %{
               circle: %{enum: "Shape", ctor: "Circle", labels: ["radius"], named: true}
             }) =~
               "fn area(shape: Shape) -> f64"
    end

    test "a ref-parameter function is rejected when emitting to Elixir" do
      assert_raise RuntimeError, ~r/`ref` is not permitted/, fn ->
        Lower.to_elixir(area(:ref), types())
      end
    end
  end
end

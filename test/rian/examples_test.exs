defmodule Rian.ExamplesTest do
  @moduledoc """
  Guards the `examples/rian/` source tour.

  Whole-file parsing of `.rian` sources awaits the declaration parser
  (ADR-0031), so the tour is illustrative — but two things about it are
  machine-checkable today and worth locking down:

    1. the tour and its README stay in sync (no undocumented or dangling file),
       so the corpus cannot drift the way the IR once did; and
    2. the expression-level constructs each file demonstrates really parse,
       lower, and lin-check through the verified passes.
  """
  use ExUnit.Case, async: true

  alias Rian.{Capability, Comptime, Lower, Pratt}

  @tour_dir Path.join([File.cwd!(), "examples", "rian"])
  @readme Path.join(@tour_dir, "README.md")

  describe "the tour and its README stay in sync" do
    test "every .rian file is linked from the tour README" do
      readme = File.read!(@readme)

      files =
        @tour_dir |> Path.join("*.rian") |> Path.wildcard() |> Enum.map(&Path.basename/1)

      assert files != [], "no .rian files found under examples/rian/"

      for f <- files do
        assert String.contains?(readme, "(#{f})"),
               "#{f} exists but is not linked from examples/rian/README.md"
      end
    end

    test "every .rian file linked from the README exists on disk" do
      linked =
        @readme
        |> File.read!()
        |> then(&Regex.scan(~r/\((\w+\.rian)\)/, &1))
        |> Enum.map(fn [_, f] -> f end)
        |> Enum.uniq()

      assert linked != [], "the README links no .rian files"

      for f <- linked do
        assert File.exists?(Path.join(@tour_dir, f)),
               "examples/rian/README.md links #{f}, which does not exist"
      end
    end
  end

  describe "expression snippets from the tour parse and lower" do
    test "operator precedence (01_basics)" do
      assert Lower.emit_expr("a + b * c", :elixir) == "a + b * c"
    end

    test "pipe + dot chains parse (01_basics, 05_modules)" do
      assert Pratt.parse("x |> greet |> String.upcase")
    end

    test "FFI atom-head call lowers (07_ffi)" do
      assert Lower.emit_expr(":lists.sum(xs)", :elixir) == ":lists.sum(xs)"
    end

    test "lambda argument parses (07_ffi, 08_lambdas_collections)" do
      assert Pratt.parse("Enum.map(xs, (x) -> x * 2)")
    end

    test "list / cons / map literals lower (08_lambdas_collections)" do
      assert Lower.emit_expr("[2, 3, 5, 7]", :elixir) == "[2, 3, 5, 7]"
      assert Lower.emit_expr("[p | rest]", :elixir) == "[p | rest]"
      assert Lower.emit_expr("%{x: 0, y: 0}", :elixir) == "%{x: 0, y: 0}"
    end

    test "comptime folds a constant expression (06_macros_comptime)" do
      folded = Comptime.fold(Pratt.parse("comptime(2 + 3 * 4)"))
      assert Lower.emit_ast(folded, :elixir) == "14"
    end

    test "wire codec call + concat lower (11_wire_formats)" do
      # `@wire`/`Bytes(len)` declarations await the parser (ADR-0037), but the
      # codec call site and its result handling are ordinary expressions today.
      assert Lower.emit_expr("m.encode()", :elixir) == "m.encode()"
      assert Lower.emit_expr("\"msg \" <> to_str(m)", :elixir) == "\"msg \" <> to_str(m)"
    end
  end

  describe "capability claims from 04_capabilities hold against the checker" do
    test "an iso handle consumed once is ok; consumed twice is rejected" do
      assert Capability.lin_check(%{"s" => :iso}, Pratt.parse("area(s)")) == :ok

      assert Capability.lin_check(%{"s" => :iso}, Pratt.parse("area(s) + area(s)")) ==
               {:error, [{"s", 2}]}
    end

    test "a val is freely shareable (this is why area's r * r is legal)" do
      assert Capability.lin_check(%{"r" => :val}, Pratt.parse("pi * r * r")) == :ok
    end

    test "linearity is branch-aware: an iso moved once per if-arm is consumed once" do
      assert Capability.lin_check(%{"f" => :iso}, Pratt.parse("if c do read(f) else drop(f) end")) ==
               :ok
    end
  end
end

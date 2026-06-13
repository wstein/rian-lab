defmodule Rian.ProtocolTest do
  # async: false — loads compiled modules into the VM.
  use ExUnit.Case, async: false

  alias Rian.{Beam, Check, Decl}
  alias Rian.Protocol.Error, as: CoherenceError

  defp load(src, mod) do
    {:ok, ^mod} = Beam.load(src, mod)
    mod
  end

  describe "protocol / impl dispatch on the BEAM (ADR-0042 part 2)" do
    test "a single-arg protocol (Show) dispatches by the receiver's runtime type" do
      m =
        load(
          """
          protocol Show do
            def show(self Self) String
          end

          impl Show for Bool do
            def show(b) := if b do "yes" else "no" end
          end

          impl Show for Int64 do
            def show(n) := "an int"
          end

          impl Show for String do
            def show(s) := s
          end
          """,
          :rian_proto_show
        )

      assert m.show(true) == "yes"
      assert m.show(false) == "no"
      assert m.show(42) == "an int"
      assert m.show("hi") == "hi"
    end

    test "a two-arg protocol (Eq) dispatches on the first argument" do
      m =
        load(
          """
          protocol Eq do
            def eq(a Self, b Self) Bool
          end

          impl Eq for Int64 do
            def eq(a, b) := a == b
          end
          """,
          :rian_proto_eq
        )

      assert m.eq(3, 3) == true
      assert m.eq(3, 4) == false
    end

    test "the impl methods are real callable functions under mangled names" do
      funcs =
        Decl.parse("""
        protocol Show do
          def show(self Self) String
        end

        impl Show for Int64 do
          def show(n) := "i"
        end
        """).funcs

      names = Enum.map(funcs, & &1.name) |> Enum.sort()
      assert names == ["impl_show_int64_show", "show"]
    end

    test "protocols work inside a module too" do
      [atom] =
        Beam.load_program("""
        mod Render do
          protocol Show do
            def show(self Self) String
          end

          impl Show for Bool do
            def show(b) := if b do "T" else "F" end
          end
        end
        """)

      assert atom.show(true) == "T"
      assert atom.show(false) == "F"
    end

    test "a method with a parametric-typed param (comma in the type) parses correctly" do
      # `Map(String, Int64)` is ONE parameter — the comma inside it must not be
      # counted as a parameter separator (paren-aware split)
      m =
        load(
          """
          protocol Keyed do
            def pick(self Self, m Map(String, Int64)) Int64
          end

          impl Keyed for Int64 do
            def pick(self, m) := self
          end

          def call(n Int64) Int64 := pick(n, %{})
          """,
          :rian_proto_parametric
        )

      assert m.call(42) == 42
    end
  end

  describe "the type gate accepts a well-typed protocol program" do
    test "Decl.compile passes the gate and emits the dispatcher + impl" do
      units =
        Decl.compile("""
        protocol Eq do
          def eq(a Self, b Self) Bool
        end

        impl Eq for Int64 do
          def eq(a, b) := a == b
        end
        """)

      # the BEAM dispatcher + impl (Elixir debug view) plus the Rust trait/impl unit
      assert Enum.map(units, &elem(&1, 0)) |> Enum.sort() ==
               ["eq", "impl_eq_int64_eq", "protocols"]

      # the dispatcher/impl carry only the Elixir view; Rust lives in `protocols`
      {_, eq} = Enum.find(units, &(elem(&1, 0) == "eq"))
      refute Map.has_key?(eq, :rust)
      {_, protos} = Enum.find(units, &(elem(&1, 0) == "protocols"))
      assert protos.rust =~ "trait RianEq"
      assert protos.rust =~ "impl RianEq for i64"
    end
  end

  describe "coherence (ADR-0042 §5)" do
    test "an impl for an unknown protocol is rejected" do
      assert_raise CoherenceError, ~r/unknown protocol `Nope`/, fn ->
        Decl.parse("impl Nope for Int64 do\n  def f(x) := x\nend\n")
      end
    end

    test "duplicate impls for the same (protocol, type) are rejected" do
      assert_raise CoherenceError, ~r/duplicate `impl P for Int64`/, fn ->
        Decl.parse("""
        protocol P do
          def m(self Self) Bool
        end

        impl P for Int64 do
          def m(x) := true
        end

        impl P for Int64 do
          def m(x) := false
        end
        """)
      end
    end

    test "an impl whose methods do not match the protocol is rejected" do
      assert_raise CoherenceError, ~r/does not match the protocol/, fn ->
        Decl.parse("""
        protocol P do
          def m(self Self) Bool
        end

        impl P for Int64 do
          def wrong(x) := true
        end
        """)
      end
    end

    test "two impl types sharing a runtime dispatch guard are rejected as ambiguous" do
      assert_raise CoherenceError, ~r/ambiguous dispatch/, fn ->
        Decl.parse("""
        protocol P do
          def m(self Self) Bool
        end

        impl P for Int64 do
          def m(x) := true
        end

        impl P for Char do
          def m(x) := false
        end
        """)
      end
    end

    test "an impl for a type with no runtime discriminator (a type variable) is rejected" do
      assert_raise CoherenceError, ~r/no runtime discriminator for `T`/, fn ->
        Decl.parse("""
        protocol Show do
          def show(self Self) String
        end

        impl Show for T do
          def show(x) := "x"
        end
        """)
      end
    end
  end

  describe "sum-type dispatch (ADR-0042 — dispatch on the constructor tag)" do
    test "dispatches a sum value by its constructor tag (tupled and nullary)" do
      m =
        load(
          """
          type Shape := Circle(r Int64) | Square(s Int64) | Unit

          protocol Kind do
            def kind(self Self) String
          end

          impl Kind for Shape do
            def kind(sh) := "shape"
          end

          impl Kind for Int64 do
            def kind(n) := "int"
          end
          """,
          :rian_proto_sum
        )

      # field-carrying variant -> tagged tuple, nullary -> bare atom
      assert m.kind({:circle, 3}) == "shape"
      assert m.kind({:square, 4}) == "shape"
      assert m.kind(:unit) == "shape"
      # a different (primitive) impl still dispatches distinctly
      assert m.kind(42) == "int"
    end

    test "a Show over a sum type with a case body (the compiler's own data shape)" do
      m =
        load(
          """
          type Expr := Num(n Int64) | Add(a Int64, b Int64) | Zero

          protocol Show do
            def show(self Self) String
          end

          impl Show for Expr do
            def show(e)
              case e do
                Num(n) -> "num"
                Add(a, b) -> "add"
                Zero -> "zero"
              end
            end
          end
          """,
          :rian_proto_sum_show
        )

      assert m.show({:num, 5}) == "num"
      assert m.show({:add, 1, 2}) == "add"
      assert m.show(:zero) == "zero"
    end

    test "dispatches a struct value by its :__struct__ tag" do
      m =
        load(
          """
          struct Point(x Int64, y Int64)

          def origin() Point := Point(0, 0)

          protocol Kind do
            def kind(self Self) String
          end

          impl Kind for Point do
            def kind(p) := "point"
          end

          impl Kind for Int64 do
            def kind(n) := "int"
          end
          """,
          :rian_proto_struct
        )

      assert m.kind(m.origin()) == "point"
      assert m.kind(7) == "int"
    end
  end

  describe "forall T: Bound enforcement (ADR-0042 §2)" do
    @base """
    protocol Eq do
      def eq(a Self, b Self) Bool
    end

    impl Eq for Int64 do
      def eq(a, b) := a == b
    end

    def same(x T, y T) Bool forall T: Eq := eq(x, y)
    """

    test "the bound is parsed onto the function" do
      f = Decl.parse(@base).funcs |> Enum.find(&(&1.name == "same"))
      assert f.bounds == %{"T" => ["Eq"]}
    end

    test "calling a bounded generic with a type that has the impl passes" do
      assert [_ | _] =
               Decl.compile(@base <> "\ndef go(a Int64, b Int64) Bool := same(a, b)\n")
    end

    test "calling a bounded generic with a type lacking the impl is a proven error" do
      assert_raise Check.Error, ~r/`same` requires `T: Eq`.*no `impl Eq for Bool`/, fn ->
        Decl.compile(@base <> "\ndef go(a Bool, b Bool) Bool := same(a, b)\n")
      end
    end

    test "an un-pinned (still-generic) call stays conservative — no rejection" do
      # `relay` forwards to `same` with its own tvar `U` (no Eq bound); the call's
      # `T` instantiates to `U`, which is not concrete, so the gate does not fire.
      src = @base <> "\ndef relay(x U, y U) Bool forall U := same(x, y)\n"
      assert [_ | _] = Decl.compile(src)
    end

    test "multiple bounds: a type missing one of them is rejected" do
      src = """
      protocol Eq do
        def eq(a Self, b Self) Bool
      end

      protocol Ord do
        def lt(a Self, b Self) Bool
      end

      impl Eq for Int64 do
        def eq(a, b) := a == b
      end

      def sorted(x T, y T) Bool forall T: Eq + Ord := eq(x, y)

      def go(a Int64, b Int64) Bool := sorted(a, b)
      """

      assert_raise Check.Error, ~r/requires `T: Ord`.*no `impl Ord for Int64`/, fn ->
        Decl.compile(src)
      end
    end
  end

  describe "Rust lowering — traits + impls + bounded generics (ADR-0061 §2)" do
    test "a protocol lowers to a fresh Rian-namespaced trait + impls + UFCS calls" do
      units =
        Decl.compile("""
        protocol Eq do
          def eq(a Self, b Self) Bool
        end

        impl Eq for Int64 do
          def eq(a, b) := a == b
        end

        def equal3(a T, b T, c T) Bool forall T: Eq := eq(a, b) and eq(b, c)
        """)

      {_, protos} = Enum.find(units, &(elem(&1, 0) == "protocols"))
      assert protos.rust =~ "trait RianEq {"
      assert protos.rust =~ "fn eq(&self, b: &Self) -> bool;"
      assert protos.rust =~ "impl RianEq for i64 {"

      {_, eq3} = Enum.find(units, &(elem(&1, 0) == "equal3"))
      # the bound becomes a real Rust trait bound; protocol calls become UFCS
      assert eq3.rust =~ "fn equal3<T: RianEq>"
      assert eq3.rust =~ "RianEq::eq(a, b)"
    end

    # each program is a single self-contained rustc compile. (Composing several
    # `Decl.compile` units into one module needs type-def dedup — `to_rust` emits
    # every type per unit — a packaging follow-up, ADR-0061.)
    defp rustc_run(rian, main, expected) do
      case System.find_executable("rustc") do
        nil ->
          :ok

        rustc ->
          rust =
            Decl.compile(rian)
            |> Enum.map(fn {_n, o} -> o[:rust] end)
            |> Enum.reject(&is_nil/1)
            |> Enum.join("\n\n")

          dir = System.tmp_dir!()
          src = Path.join(dir, "rian_proto_#{System.unique_integer([:positive])}.rs")
          bin = String.trim_trailing(src, ".rs")
          File.write!(src, rust <> "\n\nfn main() {\n#{main}\n}\n")

          {err, code} = System.cmd(rustc, ["-A", "warnings", "--edition", "2021", src, "-o", bin])
          assert code == 0, "rustc failed:\n#{err}\n--- source ---\n#{File.read!(src)}"
          {out, 0} = System.cmd(bin, [])
          File.rm(src)
          File.rm(bin)
          assert String.trim(out) == expected
      end
    end

    @tag :rust
    test "Eq over a primitive + a bounded generic compile and run under rustc" do
      rustc_run(
        """
        protocol Eq do
          def eq(a Self, b Self) Bool
        end

        impl Eq for Int64 do
          def eq(a, b) := a == b
        end

        def equal3(a T, b T, c T) Bool forall T: Eq := eq(a, b) and eq(b, c)
        """,
        """
            assert_eq!(equal3(&1i64, &1i64, &1i64), true);
            assert_eq!(equal3(&1i64, &2i64, &1i64), false);
            println!("ok");
        """,
        "ok"
      )
    end

    @tag :rust
    test "Show over a sum type (case body, String return) compiles and runs under rustc" do
      rustc_run(
        """
        type Expr := Num(n Int64) | Zero

        protocol Show do
          def show(self Self) String
        end

        impl Show for Expr do
          def show(e)
            case e do
              Num(n) -> "num"
              Zero -> "zero"
            end
          end
        end

        impl Show for Int64 do
          def show(n) := "int"
        end
        """,
        """
            assert_eq!(RianShow::show(&Expr::Num{n:5}), "num");
            assert_eq!(RianShow::show(&Expr::Zero), "zero");
            assert_eq!(RianShow::show(&7i64), "int");
            println!("ok");
        """,
        "ok"
      )
    end
  end
end

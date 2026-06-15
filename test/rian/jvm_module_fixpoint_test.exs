defmodule Rian.JvmModuleFixpointTest do
  # async: false — loads a real module into the VM via :code.load_binary.
  use ExUnit.Case, async: false

  alias Rian.{Beam, Core, Decl, JVM, Pratt}

  # Self-hosting fixpoint (ADR-0063) for the **Kotlin/JVM backend** (whole module):
  # a Rian-written port of `Rian.JVM`'s emission (compiler/jvm.rian),
  # compiled to real `.beam`, diffed against `Rian.JVM.compile` over a corpus of
  # programs in its full supported surface — sum types, multi-clause functions with
  # pattern dispatch, `if`, operators, primitives.
  #
  # The backend stage consumes Core/IR, so this test does the front-end work
  # (`Decl.parse` + `Core.from_pat`/`from_expr`) and injects the lowered IR into the
  # port; the port emits the whole Kotlin module, which must equal `Rian.JVM`'s
  # output exactly. `@external` bodies and `Rian.Shadow` rename of shadowed binds
  # are out of scope (the corpus is shadow-free).

  setup_all do
    {:ok, mod} =
      Beam.load(File.read!("compiler/jvm.rian"), :rian_jvm_module_fixpoint)

    {:ok, mod: mod}
  end

  # ── Core struct -> the port's Core sum ──
  defp ic(%Core.ENum{text: t}), do: {:c_num, t}
  defp ic(%Core.EChar{value: v}), do: {:c_char, v}
  defp ic(%Core.EStr{value: v}), do: {:c_str, v}
  defp ic(%Core.EId{name: n}), do: {:c_id, n}
  defp ic(%Core.EUnary{op: op, arg: a}), do: {:c_unary, op, ic(a)}
  defp ic(%Core.EBin{op: op, left: l, right: r}), do: {:c_bin, op, ic(l), ic(r)}

  defp ic(%Core.ECall{fun: %Core.EId{name: f}, args: args}),
    do: {:c_call, f, Enum.map(args, &ic/1)}

  defp ic(%Core.EIf{cond: c, then: t, else: e}), do: {:c_if, ic(c), iblock(t), iblock(e)}

  defp iblock(%Core.EBlock{stmts: stmts}), do: {:block, Enum.map(stmts, &istmt/1)}
  defp iblock(e), do: {:block, [{:s_expr, ic(e)}]}

  defp istmt({:bind, n, e}), do: {:s_bind, n, ic(e)}
  defp istmt({:typed_bind, n, t, e}), do: {:s_typed_bind, n, t, ic(e)}
  defp istmt({:expr, e}), do: {:s_expr, ic(e)}

  # ── Core pattern -> the port's Pat sum ──
  defp ip(%Core.PWild{}), do: :p_wild
  defp ip(%Core.PVar{name: n}), do: {:p_var, n}
  defp ip(%Core.PLit{value: v}) when is_integer(v), do: {:p_lit_int, v}
  defp ip(%Core.PLit{value: v}) when is_binary(v), do: {:p_lit_str, v}
  defp ip(%Core.PChar{value: v}), do: {:p_char, v}
  defp ip(%Core.PCtor{ctor: c, args: args}), do: {:p_ctor, c, Enum.map(args, &ip/1)}

  # ── IR -> the port's program shape ──
  defp itype(%Rian.IR.Type{name: name, variants: vs}) do
    {:type_def, name, Enum.map(vs, fn v -> {:v, v.ctor, Enum.map(v.fields, & &1.type)} end)}
  end

  defp ifunc(f) do
    clauses =
      Enum.map(f.clauses, fn c ->
        pats = Enum.map(c.pats, fn p -> ip(Core.from_pat(p)) end)
        guard = if c.guard, do: {:g_some, ic(Core.from_expr(Pratt.parse(c.guard)))}, else: :g_none
        body = iblock(Core.from_expr(Pratt.parse_body(c.body)))
        {:clause, pats, guard, body}
      end)

    params = Enum.map(f.params, fn p -> {:param, p.name, p.type} end)
    {:func, f.name, Map.get(f, :pub?, false), params, f.ret, clauses}
  end

  defp funcs_of(%{funcs: [], mods: [m]}), do: m.funcs
  defp funcs_of(%{funcs: funcs}), do: funcs
  defp types_of(%{types: [], mods: [m]}), do: m.types
  defp types_of(%{types: types}), do: types

  defp ported(mod, src) do
    prog = src |> Decl.parse() |> Rian.Opaque.erase()
    funcs = prog |> funcs_of() |> Enum.reject(&(Map.get(&1, :dispatch) == :dispatcher))
    mod.compile_prog(Enum.map(types_of(prog), &itype/1), Enum.map(funcs, &ifunc/1))
  end

  @corpus [
    "def add(a Int53, b Int53) Int53 := a + b",
    "def neg(a Int53) Int53 := -a",
    "def cmp(a Int53, b Int53) Bool := a < b and a != b or not a > b",
    "def maxi(a Int53, b Int53) Int53 := if a > b do a else b end",
    ~S|def shout(s String) String := s <> "!"|,
    "def half(a Int53, b Int53) Float64 := a / b",
    "def modrem(a Int53, b Int53) Int53 := a div b rem a",
    # multi-clause literal dispatch + recursion
    "def fib(n Int53) Int53\ndef fib(0) := 0\ndef fib(1) := 1\ndef fib(n) := fib(n - 1) + fib(n - 2)",
    # guard
    "def sign(n Int53) Int53\ndef sign(0) := 0\ndef sign(n) when n > 0 := 1\ndef sign(_) := -1",
    # sum type + nullary dispatch
    "type Color := Red | Green | Blue\npub def code(c Color) Int53\ndef code(Red) := 1\ndef code(Green) := 2\ndef code(Blue) := 3",
    # sum type with payload + ctor pattern
    "type Box := B(Int53)\ndef unbox(b Box) Int53\ndef unbox(B(n)) := n",
    "type Pair := P(Int53, Int53)\ndef fst(p Pair) Int53\ndef fst(P(a, b)) := a",
    # nested ctor pattern
    "type Wrap := W(Box)\ntype Box := B(Int53)\ndef deep(w Wrap) Int53\ndef deep(W(B(n))) := n"
  ]

  describe "self-hosting JVM-module fixpoint — Rian emitter vs Rian.JVM.compile" do
    test "the Rian-emitted Kotlin module equals Rian.JVM.compile exactly", %{mod: mod} do
      for src <- @corpus do
        assert ported(mod, src) == JVM.compile(src), "JVM module diverged on:\n#{src}"
      end
    end
  end

  describe "teeth — sum hierarchies, clause dispatch, and operator mapping are real" do
    test "a sum type emits a sealed interface + object/data class", %{mod: mod} do
      out = ported(mod, "type Color := Red | Green")
      assert out =~ "sealed interface Color"
      assert out =~ "object Red : Color"
    end

    test "a ctor pattern compiles to an `is` smart-cast + field access", %{mod: mod} do
      out = ported(mod, "type Box := B(Int53)\ndef unbox(b Box) Int53\ndef unbox(B(n)) := n")
      assert out =~ "a0 is B"
      assert out =~ "a0.f0"
    end

    test "operators map to Kotlin (== stays ==, and→&&, <>→+) and discriminate", %{mod: mod} do
      assert ported(mod, "def f(a Int53, b Int53) Bool := a == b") =~ "(a == b)"
      assert ported(mod, "def f(a Bool, b Bool) Bool := a and b") =~ "(a && b)"

      refute ported(mod, "def f(a Int53, b Int53) Int53 := a + b") ==
               ported(mod, "def f(a Int53, b Int53) Int53 := a - b")
    end
  end

  # === reference-completeness ledger (selfhost_jvm vs Rian.JVM) =================
  # Does the port reproduce `Rian.JVM.compile` for each construct the oracle
  # supports? Teeth like decl_fixpoint_test: a `ported?` flag per construct,
  # checked against reality, so a port gap can't masquerade as covered. (Oracle-
  # *unsupported* constructs — tuples/maps/structs/atoms/with/lambda/protocols/FFI
  # — are excluded; neither side handles them.)
  defp jvm_covers?(mod, src) do
    ported(mod, src) == JVM.compile(src)
  rescue
    _ -> false
  catch
    _, _ -> false
  end

  @jvm_constructs [
    {"function", "def add(a Int53, b Int53) Int53 := a + b", true},
    {"operators", "def cmp(a Int53, b Int53) Bool := a < b and a != b or not a > b", true},
    {"if-expression", "def maxi(a Int53, b Int53) Int53 := if a > b do a else b end", true},
    {"div/rem + float `/`", "def half(a Int53, b Int53) Float64 := a / b", true},
    {"when guard",
     "def sign(n Int53) Int53\ndef sign(0) := 0\ndef sign(n) when n > 0 := 1\ndef sign(_) := -1",
     true},
    {"string `<>`", "def shout(s String) String := s <> \"!\"", true},
    {"sum type (sealed)",
     "type Color := Red | Green | Blue\npub def code(c Color) Int53\n" <>
       "def code(Red) := 1\ndef code(Green) := 2\ndef code(Blue) := 3", true},
    {"ctor pattern (payload)",
     "type Box := B(Int53)\ndef unbox(b Box) Int53\ndef unbox(B(n)) := n", true},
    {"nested ctor pattern",
     "type Box := B(Int53)\ntype Wrap := W(Box)\ndef deep(w Wrap) Int53\ndef deep(W(B(n))) := n",
     true},
    {"literal dispatch + recursion",
     "def fib(n Int53) Int53\ndef fib(0) := 0\ndef fib(1) := 1\ndef fib(n) := fib(n - 1) + fib(n - 2)",
     true},
    # --- oracle supports, port does NOT yet (no ic/ip clause in selfhost_jvm) ---
    {"case",
     "type Shape := Circle(Int53) | Square(Int53)\ndef area(s Shape) Int53 := case s do\n" <>
       "  Circle(r) -> r\n  Square(x) -> x\nend", false},
    {"lists / Vec",
     "def hd(xs Vec(Int53), d Int53) Int53\ndef hd([], d) := d\ndef hd([h | t], _) := h", false},
    {"char literal", "def kind(c Char) Int64\ndef kind('a') := 1\ndef kind(_) := 0", true},
    # --- oracle supports, port does NOT yet ---
    {"Str/Char prims", "def d(c Char) Int64 := Prim.char_code(c) - Prim.char_code('0')", false}
  ]

  describe "JVM backend completeness ledger (selfhost_jvm vs Rian.JVM)" do
    test "the oracle compiles every listed construct — corpus is valid" do
      for {name, src, _} <- @jvm_constructs do
        assert is_binary(JVM.compile(src)), "Rian.JVM rejected the `#{name}` example — fix it"
      end
    end

    test "every construct's ported? flag matches reality", %{mod: mod} do
      drift =
        for {name, src, ported?} <- @jvm_constructs,
            actual = jvm_covers?(mod, src),
            actual != ported? do
          "#{name}: ledger says ported?=#{ported?} but selfhost_jvm " <>
            "#{if actual, do: "REPRODUCES", else: "does NOT reproduce"} Rian.JVM"
        end

      assert drift == [], "JVM backend completeness ledger drifted:\n" <> Enum.join(drift, "\n")
    end

    test "construct coverage is measured and must not regress" do
      ported = Enum.count(@jvm_constructs, fn {_, _, p} -> p end)
      total = length(@jvm_constructs)
      IO.puts("\n  selfhost_jvm backend completeness: #{ported}/#{total} Rian.JVM constructs")
      assert ported >= 10
    end
  end
end

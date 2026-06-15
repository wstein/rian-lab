defmodule Rian.JsModuleFixpointTest do
  # async: false — loads a real module into the VM via :code.load_binary.
  use ExUnit.Case, async: false

  alias Rian.{Beam, Core, Decl, JS, Pratt}

  # Self-hosting fixpoint (ADR-0063) for the **ECMAScript backend** (whole module):
  # a Rian-written port of `Rian.JS`'s emission (compiler/js.rian),
  # compiled to real `.beam`, diffed against `Rian.JS.compile` over a corpus
  # covering its expression + function surface — sum variants (tagged arrays),
  # structs, tuples/lists/maps, `.field`, `if`, `case`, multi-clause dispatch.
  #
  # The backend stage consumes Core/IR, so this test does the front-end work and
  # injects the lowered IR; the port emits the whole module, which must equal
  # `Rian.JS`'s output exactly. The corpus is number-mode (`Int53`), shadow-free,
  # and protocol-free (protocol dispatch / int-mode / Shadow are out of scope).

  setup_all do
    {:ok, mod} = Beam.load(File.read!("compiler/js.rian"), :rian_js_module_fixpoint)
    {:ok, mod: mod}
  end

  # ── Core struct -> the port's Core sum ──
  defp ic(%Core.ENum{text: t}), do: {:c_num, t}
  defp ic(%Core.EChar{value: v}), do: {:c_char, v}
  defp ic(%Core.EStr{value: v}), do: {:c_str, v}
  defp ic(%Core.EId{name: n}), do: {:c_id, n}
  defp ic(%Core.EAtom{name: a}), do: {:c_atom, a}
  defp ic(%Core.EUnary{op: op, arg: a}), do: {:c_unary, op, ic(a)}
  defp ic(%Core.EBin{op: op, left: l, right: r}), do: {:c_bin, op, ic(l), ic(r)}

  defp ic(%Core.ECall{fun: %Core.EId{name: f}, args: [%Core.ELabel{} | _] = args}),
    do: {:c_struct, f, Enum.map(args, fn %Core.ELabel{name: k, expr: e} -> {:p, k, ic(e)} end)}

  defp ic(%Core.ECall{fun: %Core.EId{name: f}, args: args}),
    do: {:c_call, f, Enum.map(args, &ic/1)}

  defp ic(%Core.ETuple{elems: es}), do: {:c_tuple, Enum.map(es, &ic/1)}
  defp ic(%Core.EList{elems: es, tail: :close}), do: {:c_list, Enum.map(es, &ic/1), :t_close}
  defp ic(%Core.EList{elems: es, tail: t}), do: {:c_list, Enum.map(es, &ic/1), {:t_tail, ic(t)}}

  defp ic(%Core.EMap{pairs: pairs}),
    do: {:c_map, Enum.map(pairs, fn {k, v} -> {:p, k, ic(v)} end)}

  defp ic(%Core.EStruct{name: name, pairs: pairs}),
    do: {:c_struct, to_string(name), Enum.map(pairs, fn {k, v} -> {:p, k, ic(v)} end)}

  defp ic(%Core.EDot{head: h, name: f}), do: {:c_dot, ic(h), f}
  defp ic(%Core.EIf{cond: c, then: t, else: e}), do: {:c_if, ic(c), iblock(t), iblock(e)}
  defp ic(%Core.ECase{scrut: s, arms: arms}), do: {:c_case, ic(s), Enum.map(arms, &iarm/1)}

  defp iblock(%Core.EBlock{stmts: stmts}), do: {:block, Enum.map(stmts, &istmt/1)}
  defp iblock(e), do: {:block, [{:s_expr, ic(e)}]}

  defp istmt({:bind, n, e}), do: {:s_bind, n, ic(e)}
  defp istmt({:typed_bind, n, t, e}), do: {:s_typed_bind, n, t, ic(e)}
  defp istmt({:expr, e}), do: {:s_expr, ic(e)}

  defp iarm({p, g, b}), do: {:arm, ip(p), iguard(g), iblock(b)}
  defp iguard(nil), do: :g_none
  defp iguard(g), do: {:g_some, ic(g)}

  # ── Core pattern -> the port's Pat sum ──
  defp ip(%Core.PWild{}), do: :p_wild
  defp ip(%Core.PVar{name: n}), do: {:p_var, n}
  defp ip(%Core.PLit{value: v}) when is_integer(v), do: {:p_lit_int, v}
  defp ip(%Core.PLit{value: v}) when is_binary(v), do: {:p_lit_str, v}
  defp ip(%Core.PChar{value: v}), do: {:p_char, v}
  defp ip(%Core.PAtom{name: a}), do: {:p_atom, a}
  defp ip(%Core.PCtor{ctor: c, args: args}), do: {:p_ctor, c, Enum.map(args, &ip/1)}
  defp ip(%Core.PTuple{elems: es}), do: {:p_tuple, Enum.map(es, &ip/1)}
  defp ip(%Core.PList{elems: es, tail: :close}), do: {:p_list, Enum.map(es, &ip/1), :ptl_close}
  defp ip(%Core.PList{elems: es, tail: t}), do: {:p_list, Enum.map(es, &ip/1), {:ptl_tail, ip(t)}}

  # ── IR func -> the port's Func ──
  defp ifunc(f) do
    clauses =
      Enum.map(f.clauses, fn c ->
        pats = Enum.map(c.pats, fn p -> ip(Core.from_pat(p)) end)
        guard = if c.guard, do: {:g_some, ic(Core.from_expr(Pratt.parse(c.guard)))}, else: :g_none
        body = iblock(Core.from_expr(Pratt.parse_body(c.body)))
        {:clause, pats, guard, body}
      end)

    {:func, f.name, Map.get(f, :pub?, false), length(hd(f.clauses).pats), clauses}
  end

  defp funcs_of(%{funcs: [], mods: [m]}), do: m.funcs
  defp funcs_of(%{funcs: funcs}), do: funcs

  defp ported(mod, src) do
    prog = src |> Decl.parse() |> Rian.Opaque.erase()
    funcs = prog |> funcs_of() |> Enum.reject(&(Map.get(&1, :dispatch) == :dispatcher))
    mod.compile_prog(Enum.map(funcs, &ifunc/1))
  end

  @corpus [
    "def add(a Int53, b Int53) Int53 := a + b",
    "def neg(a Int53) Int53 := -a",
    "def cmp(a Int53, b Int53) Bool := a < b and a != b or not a > b",
    "def quot(a Int53, b Int53) Int53 := a div b rem a",
    ~S|def shout(s String, n Int53) String := s <> "!"|,
    "def maxi(a Int53, b Int53) Int53 := if a > b do a else b end",
    # multi-clause literal dispatch + recursion
    "def fib(n Int53) Int53\ndef fib(0) := 0\ndef fib(1) := 1\ndef fib(n) := fib(n - 1) + fib(n - 2)",
    # guard
    "def sign(n Int53) Int53\ndef sign(0) := 0\ndef sign(n) when n > 0 := 1\ndef sign(_) := -1",
    # sum variants: construction (tagged array) + ctor dispatch
    "type Opt := None | Some(Int53)\npub def mk(n Int53) Opt\ndef mk(0) := None\ndef mk(n) := Some(n)",
    "type Opt := None | Some(Int53)\ndef get(o Opt, d Int53) Int53\ndef get(None, d) := d\ndef get(Some(v), _) := v",
    # tuple construction (Result) + tuple patterns in a case
    "type E := Bad\ndef ok(x Int53) Int53 | E := {:ok, x}",
    "def chk(x Int53) Int53 := case {:ok, x} do\n  {:ok, v} -> v\n  _ -> 0\nend",
    # list construction + cons dispatch
    "def hd(xs Vec(Int53), d Int53) Int53\ndef hd([], d) := d\ndef hd([h | t], _) := h",
    "def cons(x Int53, xs Vec(Int53)) Vec(Int53) := [x | xs]",
    # atoms / case-expression
    "def tag(b Bool) Symbol := if b do :yes else :no end",
    "def classify(n Int53) Int53 := case n do\n  0 -> 10\n  m -> m + 1\nend"
  ]

  describe "self-hosting JS-module fixpoint — Rian emitter vs Rian.JS.compile" do
    test "the Rian-emitted JS module equals Rian.JS.compile exactly", %{mod: mod} do
      for src <- @corpus do
        assert ported(mod, src) == JS.compile(src), "JS module diverged on:\n#{src}"
      end
    end
  end

  describe "teeth — variants, dispatch, and JS operator/value encoding are real" do
    test "a sum variant is a tagged array; a ctor pattern checks the head", %{mod: mod} do
      assert ported(mod, "def mk(n Int53) Opt\ndef mk(0) := None\ndef mk(n) := Some(n)") =~
               ~s(["Some", n])

      out = ported(mod, "def get(o Opt) Int53\ndef get(Some(v)) := v")
      assert out =~ ~s(a0[0] === "Some")
      assert out =~ "a0[1]"
    end

    test "JS operator/value encoding (===, &&, atoms→strings, div→Math.trunc)", %{mod: mod} do
      assert ported(mod, "def f(a Int53, b Int53) Bool := a == b") =~ "(a === b)"
      assert ported(mod, "def f(a Int53, b Int53) Int53 := a div b") =~ "Math.trunc(a / b)"
      assert ported(mod, "def f() Sym := :ok") =~ ~s("ok")
    end

    test "discriminates structure", %{mod: mod} do
      refute ported(mod, "def f(a Int53, b Int53) Int53 := a + b") ==
               ported(mod, "def f(a Int53, b Int53) Int53 := a - b")
    end
  end

  # === reference-completeness ledger (selfhost_js vs Rian.JS) ===================
  defp js_covers?(mod, src) do
    ported(mod, src) == JS.compile(src)
  rescue
    _ -> false
  catch
    _, _ -> false
  end

  @js_constructs [
    {"function", "def add(a Int53, b Int53) Int53 := a + b", true},
    {"operators", "def cmp(a Int53, b Int53) Bool := a < b and a != b or not a > b", true},
    {"if (ternary)", "def maxi(a Int53, b Int53) Int53 := if a > b do a else b end", true},
    {"when guard",
     "def sign(n Int53) Int53\ndef sign(0) := 0\ndef sign(n) when n > 0 := 1\ndef sign(_) := -1",
     true},
    {"sum variants",
     "type Opt := None | Some(Int53)\ndef get(o Opt, d Int53) Int53\n" <>
       "def get(None, d) := d\ndef get(Some(v), _) := v", true},
    {"Result + tuple",
     "type E := Bad\ndef half(n Int53) Int53 | E\ndef half(0) := {:error, Bad}\ndef half(n) := {:ok, n}",
     true},
    {"case (IIFE)", "def classify(n Int53) Int53 := case n do\n  0 -> 10\n  m -> m + 1\nend",
     true},
    {"lists / cons",
     "def hd(xs Vec(Int53), d Int53) Int53\ndef hd([], d) := d\ndef hd([h | t], _) := h", true},
    {"atoms / Symbol", "def tag(b Bool) Symbol := if b do :yes else :no end", true},
    {"string `<>`", "def shout(s String) String := s <> \"!\"", true},
    {"char literal", "def kind(c Char) Int53\ndef kind('a') := 1\ndef kind(_) := 0", true},
    {"struct", "struct P(x Int53, y Int53)\ndef getx(p P) Int53 := p.x", true},
    # --- oracle supports, port does NOT (program-level / separate subsystem) ---
    {"protocol dispatch",
     "protocol Show do\n  def show(x Int53) String\nend\nimpl Show for Int53 do\n" <>
       "  def show(n) := \"x\"\nend\ndef render(x Int53) String := show(x)", false}
  ]

  describe "JS backend completeness ledger (selfhost_js vs Rian.JS)" do
    test "the oracle compiles every listed construct — corpus is valid" do
      for {name, src, _} <- @js_constructs do
        assert is_binary(JS.compile(src)), "Rian.JS rejected the `#{name}` example — fix it"
      end
    end

    test "every construct's ported? flag matches reality", %{mod: mod} do
      drift =
        for {name, src, ported?} <- @js_constructs,
            actual = js_covers?(mod, src),
            actual != ported? do
          "#{name}: ledger says ported?=#{ported?} but selfhost_js " <>
            "#{if actual, do: "REPRODUCES", else: "does NOT reproduce"} Rian.JS"
        end

      assert drift == [], "JS backend completeness ledger drifted:\n" <> Enum.join(drift, "\n")
    end

    test "construct coverage is measured and must not regress" do
      ported = Enum.count(@js_constructs, fn {_, _, p} -> p end)
      total = length(@js_constructs)
      IO.puts("\n  selfhost_js backend completeness: #{ported}/#{total} Rian.JS constructs")
      assert ported >= 10
    end
  end
end

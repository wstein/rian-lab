defmodule Rian.RustModuleFixpointTest do
  # async: false — loads a real module into the VM via :code.load_binary.
  use ExUnit.Case, async: false

  alias Rian.{Beam, Capability, Core, Decl, Lower, Pratt}

  # Self-hosting fixpoint (ADR-0063) for the **Rust text backend** (whole module):
  # a Rian-written port of `Rian.Lower.rust_program`'s emission
  # (examples/rian/selfhost_rust.rian), compiled to real `.beam`, diffed against
  # `Rian.Lower.rust_program` over a corpus — sum types → `enum`s, functions with
  # `match`-tuple multi-clause dispatch, operators, `if`, variant construct+match.
  #
  # The emitter consumes RESOLVED + capability-LOWERED Core: this test does the
  # upstream work (parse, build the ctor→enum + struct meta, `Capability.rust_param`,
  # resolve variant/struct construction) and injects, then the port emits the
  # module. Structs (decl/construct/field) and closed + cons lists are now covered;
  # generics, maps, String-returns, the Elixir target, and struct *patterns* (a
  # reference gap — Rian.Lower raises) are out of scope (the corpus is non-generic).

  setup_all do
    {:ok, mod} =
      Beam.load(File.read!("examples/rian/selfhost_rust.rian"), :rian_rust_module_fixpoint)

    {:ok, mod: mod}
  end

  # ctor (snake) -> %{enum, ctor, named, labels} over a program's sum types, plus a
  # struct-name (snake) -> %{struct: name} marker so `ic` can tell a struct
  # construction (`Point { … }`) from a named-variant construction.
  defp build_meta(types, structs) do
    variants =
      for t <- types, v <- t.variants, into: %{} do
        labels = Enum.map(v.fields, & &1.label)
        named = v.fields != [] and Enum.all?(labels, & &1)

        {Rian.PatternLower.to_snake(v.ctor),
         %{enum: t.name, ctor: v.ctor, named: named, labels: labels}}
      end

    structs_meta =
      for s <- structs, into: %{}, do: {Rian.PatternLower.to_snake(s.name), %{struct: s.name}}

    Map.merge(variants, structs_meta)
  end

  # ── resolved body Core -> the port's Core ──
  defp ic(%Core.EBlock{stmts: [{:expr, e}]}, m), do: ic(e, m)
  defp ic(%Core.ENum{text: t}, _), do: {:c_num, t}
  defp ic(%Core.EStr{value: v}, _), do: {:c_str, v}
  defp ic(%Core.EUnary{op: op, arg: a}, m), do: {:c_unary, op, ic(a, m)}
  defp ic(%Core.EBin{op: op, left: l, right: r}, m), do: {:c_bin, op, ic(l, m), ic(r, m)}

  defp ic(%Core.EIf{cond: c, then: t, else: e}, m),
    do: {:c_if, ic(c, m), ibranch(t, m), ibranch(e, m)}

  defp ic(%Core.ETuple{elems: [%Core.EAtom{name: "ok"}, v]}, m), do: {:c_ok, ic(v, m)}
  defp ic(%Core.ETuple{elems: [%Core.EAtom{name: "error"}, e]}, m), do: {:c_err, ic(e, m)}
  defp ic(%Core.ETuple{elems: es}, m), do: {:c_tuple, Enum.map(es, &ic(&1, m))}

  defp ic(%Core.ECall{fun: %Core.EId{name: f}, args: args}, m) do
    cond do
      match?(%{struct: _}, Map.get(m, Rian.PatternLower.to_snake(f))) ->
        {:c_struct, f,
         Enum.map(args, fn %Core.ELabel{name: l, expr: e} -> {:vp, l, ic(e, m)} end)}

      pascal?(f) ->
        variant(f, Enum.map(args, fn a -> {"", a} end), m)

      true ->
        {:c_call, f, Enum.map(args, &ic(&1, m))}
    end
  end

  defp ic(%Core.EId{name: n}, m), do: if(pascal?(n), do: variant(n, [], m), else: {:c_id, n})
  defp ic(%Core.EDot{head: h, name: f}, m), do: {:c_dot, ic(h, m), f}

  defp ic(%Core.EList{elems: es, tail: :close}, m),
    do: {:c_list, Enum.map(es, &ic(&1, m)), :l_close}

  defp ic(%Core.EList{elems: es, tail: t}, m),
    do: {:c_list, Enum.map(es, &ic(&1, m)), {:l_cons, ic(t, m)}}

  defp ibranch(%Core.EBlock{stmts: [{:expr, e}]}, m), do: ic(e, m)
  defp ibranch(e, m), do: ic(e, m)

  defp variant(ctor, lab_vals, m) do
    info = Map.fetch!(m, Rian.PatternLower.to_snake(ctor))
    pairs = Enum.map(lab_vals, fn {l, v} -> {:vp, l, ic(v, m)} end)
    {:c_variant, info.enum, info.ctor, info.named, pairs}
  end

  # ── resolved pattern -> the port's RPat ──
  defp rp(%Core.PWild{}, _), do: :r_wild
  defp rp(%Core.PVar{name: n}, _), do: {:r_var, n}
  defp rp(%Core.PLit{value: v}, _) when is_integer(v), do: {:r_int, v}
  defp rp(%Core.PLit{value: v}, _) when is_binary(v), do: {:r_str, v}
  defp rp(%Core.PTuple{elems: [%Core.PAtom{name: "ok"}, p]}, m), do: {:r_ok_p, rp(p, m)}
  defp rp(%Core.PTuple{elems: [%Core.PAtom{name: "error"}, p]}, m), do: {:r_err_p, rp(p, m)}
  defp rp(%Core.PTuple{elems: ps}, m), do: {:r_tuple_p, Enum.map(ps, &rp(&1, m))}

  defp rp(%Core.PCtor{ctor: c, args: args}, m) do
    info = Map.fetch!(m, Rian.PatternLower.to_snake(c))
    {:r_ctor_p, info.enum, info.ctor, info.named, info.labels || [], Enum.map(args, &rp(&1, m))}
  end

  defp pascal?(<<c, _::binary>>), do: c in ?A..?Z

  # ── IR -> the port's program shape ──
  defp ienum(t) do
    vs =
      Enum.map(t.variants, fn v ->
        labels = Enum.map(v.fields, & &1.label)
        named = v.fields != [] and Enum.all?(labels, & &1)
        {:e_var, v.ctor, Enum.map(v.fields, &Capability.owned(&1.type)), named, labels}
      end)

    {:enum_def, t.name, vs}
  end

  defp istruct(s) do
    {:struct_def, s.name,
     Enum.map(s.fields, fn f -> {:param, f.label, Capability.owned(f.type)} end)}
  end

  defp ifunc(f, m) do
    params =
      Enum.map(f.params, fn p -> {:param, p.name, Capability.rust_param(p.cap, p.type)} end)

    clauses =
      Enum.map(f.clauses, fn c ->
        pats = Enum.map(c.pats, fn p -> rp(Core.from_pat(p), m) end)

        guard =
          if c.guard, do: {:g_some, ic(Core.from_expr(Pratt.parse(c.guard)), m)}, else: :g_none

        body = ic(Core.from_expr(Pratt.parse_body(c.body)), m)
        {:clause, pats, guard, body}
      end)

    {:func, f.name, Map.get(f, :pub?, false), params, Capability.owned(f.ret), clauses}
  end

  defp ported(mod, src) do
    prog = src |> Decl.parse() |> Rian.Opaque.erase()
    m = build_meta(prog.types, prog.structs)
    funcs = prog.funcs |> Enum.reject(& &1.dispatch)

    mod.compile_prog(
      Enum.map(prog.structs, &istruct/1),
      Enum.map(prog.types, &ienum/1),
      Enum.map(funcs, fn f -> ifunc(f, m) end)
    )
  end

  @corpus [
    "def add(a Int64, b Int64) Int64 := a + b",
    "def neg(a Int64) Int64 := -a",
    "def cmp(a Int64, b Int64) Bool := a < b and a != b",
    "def quot(a Int64, b Int64) Int64 := a div b rem a",
    "def maxi(a Int64, b Int64) Int64 := if a > b do a else b end",
    "def fib(n Int64) Int64\ndef fib(0) := 0\ndef fib(1) := 1\ndef fib(n) := fib(n - 1) + fib(n - 2)",
    "def sign(n Int64) Int64\ndef sign(0) := 0\ndef sign(n) when n > 0 := 1\ndef sign(_) := -1",
    # sum type -> enum; variant construct + ctor-pattern match
    "type Opt := None | Some(Int64)\npub def mk(n Int64) Opt\ndef mk(0) := None\ndef mk(n) := Some(n)",
    "type Opt := None | Some(Int64)\npub def get(o Opt, d Int64) Int64\ndef get(None, d) := d\ndef get(Some(v), _) := v",
    "type RGB := Red | Green | Blue\npub def code(c RGB) Int64\ndef code(Red) := 1\ndef code(Green) := 2\ndef code(Blue) := 3",
    # structs: decl → `struct N { … }`, named construction, field access
    "struct Point(x Int64, y Int64)\ndef mk(a Int64, b Int64) Point := Point(x: a, y: b)\ndef getx(p val Point) Int64 := p.x",
    # closed list + cons construction (iso tail owns the Vec)
    "def two() Vec(Int64) := [1, 2]",
    "def pre(x Int64, xs iso Vec(Int64)) Vec(Int64) := [x | xs]",
    "def pre2(a Int64, b Int64, xs iso Vec(Int64)) Vec(Int64) := [a, b | xs]"
  ]

  describe "self-hosting Rust-module fixpoint — Rian emitter vs Rian.Lower.rust_program" do
    test "the Rian-emitted Rust module equals Rian.Lower.rust_program exactly", %{mod: mod} do
      for src <- @corpus do
        assert ported(mod, src) == Lower.rust_program(Decl.parse(src)),
               "Rust module diverged on:\n#{src}"
      end
    end
  end

  describe "teeth — enums, match dispatch, and capability-lowered signatures are real" do
    test "a sum type emits a derive'd enum; a val param borrows (&Opt)", %{mod: mod} do
      out =
        ported(
          mod,
          "type Opt := None | Some(Int64)\ndef get(o Opt, d Int64) Int64\ndef get(None, d) := d\ndef get(Some(v), _) := v"
        )

      assert out =~ "#[derive(Clone, Debug, PartialEq)]\nenum Opt {"
      assert out =~ "o: &Opt"
      assert out =~ "Opt::Some(v)"
    end

    test "multi-clause dispatch is a match over the param tuple", %{mod: mod} do
      out =
        ported(mod, "def add(a Int64, b Int64) Int64\ndef add(0, b) := b\ndef add(a, b) := a + b")

      assert out =~ "match (a, b) {"
      assert out =~ "(0, b) =>"
    end

    test "discriminates structure", %{mod: mod} do
      refute ported(mod, "def f(a Int64, b Int64) Int64 := a + b") ==
               ported(mod, "def f(a Int64, b Int64) Int64 := a - b")
    end

    test "a struct emits a derive'd record, named construction, and field access", %{mod: mod} do
      out =
        ported(
          mod,
          "struct Point(x Int64, y Int64)\ndef mk(a Int64, b Int64) Point := Point(x: a, y: b)\ndef getx(p val Point) Int64 := p.x"
        )

      assert out =~ "#[derive(Clone, Debug, PartialEq)]\nstruct Point { x: i64, y: i64 }"
      # a record construction is `Name { … }` — NO `Enum::` prefix
      assert out =~ "Point { x: a, y: b }"
      refute out =~ "Point::"
      assert out =~ "=> p.x,"
    end

    test "a cons list prepends onto an owned tail; a closed list is `vec![…]`", %{mod: mod} do
      assert ported(mod, "def two() Vec(Int64) := [1, 2]") =~ "vec![1, 2]"

      cons = ported(mod, "def pre(x Int64, xs iso Vec(Int64)) Vec(Int64) := [x | xs]")
      assert cons =~ "{ let mut __v = xs.to_vec(); __v.insert(0, x); __v }"
    end
  end
end

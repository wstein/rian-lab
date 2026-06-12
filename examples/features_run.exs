alias Rian.Lower

IO.puts("===== LOWERING (Rian expr -> Elixir | Rust) =====")
gallery = [
  "(x) -> x * 2",
  ":lists.foldl((x, acc) -> x + acc, 0, xs)",
  "if n >= 0 do 1 else 0 - 1 end",
  "if n > 0 do a := n * 2; a + 1 else 0 end",
  "[1, 2, 3]",
  "[h | t]",
  "%{a: 1, b: 2}"
]
Enum.each(gallery, fn s ->
  el = Lower.emit_expr(s, :elixir)
  rs = try do Lower.emit_expr(s, :rust) rescue e -> "(BEAM-only: #{Exception.message(e)})" end
  :io.format("~-42s~n   elixir: ~s~n   rust:   ~s~n", [s, el, rs])
end)

IO.puts("\n===== EXECUTE ON THE BEAM =====")
funcs = [
  {%{name: "dbl_all", params: [%{name: "xs", type: "Vec(Int64)", cap: :val}], ret: "Vec(Int64)",
     clauses: [%{pats: [{:var, "xs"}], body: "Enum.map(xs, (x) -> x * 2)"}]}, [[1,2,3]], [2,4,6]},
  {%{name: "sum", params: [%{name: "xs", type: "Vec(Int64)", cap: :val}], ret: "Int64",
     clauses: [%{pats: [{:var, "xs"}], body: ":lists.foldl((x, acc) -> x + acc, 0, xs)"}]}, [[1,2,3,4]], 10},
  {%{name: "sign", params: [%{name: "n", type: "Int64", cap: :val}], ret: "Int64",
     clauses: [%{pats: [{:var, "n"}], body: "if n >= 0 do 1 else 0 - 1 end"}]}, [-5], -1},
  {%{name: "step", params: [%{name: "n", type: "Int64", cap: :val}], ret: "Int64",
     clauses: [%{pats: [{:var, "n"}], body: "if n > 0 do a := n * 2; a + 1 else 0 end"}]}, [3], 7},
  {%{name: "nums", params: [%{name: "_x", type: "Int64", cap: :val}], ret: "Vec(Int64)",
     clauses: [%{pats: [{:var, "_x"}], body: "[10, 20, 30]"}]}, [0], [10,20,30]},
  {%{name: "pre", params: [%{name: "p", type: "Int64", cap: :val}], ret: "Vec(Int64)",
     clauses: [%{pats: [{:var, "p"}], body: "[p | [1, 2]]"}]}, [0], [0,1,2]},
  {%{name: "rec", params: [%{name: "_x", type: "Int64", cap: :val}], ret: "Map",
     clauses: [%{pats: [{:var, "_x"}], body: "%{a: 1, b: 2}"}]}, [0], %{a: 1, b: 2}}
]
defs = Enum.map_join(funcs, "\n", fn {f,_,_} -> Lower.compile_beam([], f).elixir |> String.split("\n") |> List.last() end)
Code.eval_string("defmodule Feat do\n#{defs}\nend")
Enum.each(funcs, fn {f, args, exp} ->
  got = apply(Feat, String.to_atom(f.name), args)
  :io.format("~-9s ~p => ~p   ~s~n", [f.name, args, got, (if got == exp, do: "OK", else: "WRONG #{inspect exp}")])
end)

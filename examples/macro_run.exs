alias Rian.{Pratt, Macro, Comptime, Lower}

env = Macro.build_env([
  %{name: "unless", params: ["cond", "body"], template: "if not cond do body else 0 end"},
  %{name: "square", params: ["x"], template: "x * x"},
  %{name: "add_tmp", params: ["x"], template: "if true do tmp := 100; x + tmp else 0 end"}
])

pipeline = fn src -> Pratt.parse(src) |> (&Macro.expand(env, &1)).() |> Comptime.fold() end

IO.puts("===== MACRO + COMPTIME LOWERING =====")
cases = [
  {"unless(n > 5, n * 10)", "unless -> if/not"},
  {"square(a + b)", "AST macro: no C-preprocessor precedence bug"},
  {"add_tmp(tmp)", "hygiene: macro-local tmp must not capture caller tmp"},
  {"comptime(2 + 3 * 4)", "comptime fold"},
  {"comptime((1 + 2) * 5)", "comptime fold"}
]
Enum.each(cases, fn {src, note} ->
  ast = pipeline.(src)
  el = Lower.emit_ast(ast, :elixir)
  rs = try do Lower.emit_ast(ast, :rust) rescue e -> "(BEAM-only: #{Exception.message(e)})" end
  :io.format("~-26s ~s~n   elixir: ~s~n   rust:   ~s~n", [src, note, el, rs])
end)

IO.puts("\n===== SANDBOX: comptime refuses effects =====")
Enum.each(["comptime(foo(3))", "comptime(x + 1)", "comptime(:lists.sum(xs))"], fn src ->
  r = try do pipeline.(src); "ALLOWED (bug!)" rescue e -> "refused: " <> Exception.message(e) end
  :io.format("~-26s ~s~n", [src, r])
end)

IO.puts("\n===== EXECUTE ON THE BEAM =====")
funcs = [
  {"t", "n", "unless(n > 5, n * 10)", [3], 30},
  {"t7", "n", "unless(n > 5, n * 10)", [7], 0},
  {"sq", "m", "square(m + 1)", [4], 25},
  {"hyg", "tmp", "add_tmp(tmp)", [5], 105},
  {"c", "_x", "comptime(2 + 3 * 4)", [0], 14}
]
defs = Enum.map_join(funcs, "\n", fn {name, p, body, _, _} ->
  "def #{name}(#{p}) do #{Lower.emit_ast(pipeline.(body), :elixir)} end"
end)
Code.eval_string("defmodule Mac do\n#{defs}\nend")
Enum.each(funcs, fn {name, _, _, args, exp} ->
  got = apply(Mac, String.to_atom(name), args)
  :io.format("~-5s ~p => ~p   ~s~n", [name, args, got, (if got == exp, do: "OK", else: "WRONG exp #{inspect exp}")])
end)

# Rust: compile the expanded outputs
unless_rs = Lower.emit_ast(pipeline.("unless(n > 5, n * 10)"), :rust)
square_rs = Lower.emit_ast(pipeline.("square(m + 1)"), :rust)
hyg_rs    = Lower.emit_ast(pipeline.("add_tmp(tmp)"), :rust)
ct_rs     = Lower.emit_ast(pipeline.("comptime(2 + 3 * 4)"), :rust)
File.write!("macro.rs", """
#![allow(unused)]
fn main() {
    let n = 3i64;  let u = #{unless_rs};      assert_eq!(u, 30);
    let m = 4i64;  let s = #{square_rs};      assert_eq!(s, 25);
    let tmp = 5i64; let h = #{hyg_rs};        assert_eq!(h, 105);
    let c = #{ct_rs};                          assert_eq!(c, 14);
    println!("rust macros OK: u={} s={} h={} c={}", u, s, h, c);
}
""")
IO.puts("\n[wrote macro.rs]")

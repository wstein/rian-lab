alias Rian.Lower

IO.puts("===== DOT SYNTAX LOWERING (Rian source uses `.`) =====")
Enum.each(["Geometry.area(x)", "point.x", "Value.Num(n)", ":lists.sum(xs)"], fn s ->
  el = Lower.emit_expr(s, :elixir)
  rs = try do Lower.emit_expr(s, :rust) rescue _ -> "(BEAM-only)" end
  :io.format("~-20s elixir: ~-22s rust: ~s~n", [s, el, rs])
end)

IO.puts("\n===== USER EXAMPLE: match on Value.Num(x) =====")
types = [%{name: "Value", variants: [
  %{ctor: "Num", fields: [%{type: "i64"}]},
  %{ctor: "Zero", fields: []}
]}]
eval = %{name: "eval", param_name: "v", param_type: "Value", param_cap: :iso, ret: "i64",
  clauses: [
    %{pats: [{:ctor, "Num", [{:var, "n"}]}], body: "n * 2"},
    %{pats: [{:ctor, "Zero", []}], body: "0"}
  ]}
out = Lower.compile(types, eval)
IO.puts("--- Emitted Elixir ---"); IO.puts(out.elixir)
IO.puts("\n--- Emitted Rust ---"); IO.puts(out.rust)

Code.eval_string("defmodule Ev do\n#{out.elixir}\nend")
IO.puts("\n--- Execute Elixir ---")
:io.format("eval({:num, 21}) = ~p   eval(:zero) = ~p~n", [Ev.eval({:num, 21}), Ev.eval(:zero)])

File.write!("value.rs", "#![allow(dead_code)]\n" <> out.rust <> "\n\n\nfn main() {\n    assert_eq!(eval(Value::Num(21)), 42);\n    assert_eq!(eval(Value::Zero), 0);\n    println!(\"rust eval(Num(21))={} eval(Zero)={}\", eval(Value::Num(21)), eval(Value::Zero));\n}\n")

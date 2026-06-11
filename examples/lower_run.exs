alias Rian.Lower

types = [
  %{
    name: "Shape",
    variants: [
      %{ctor: "Circle", fields: [%{label: "radius", type: "f64"}]},
      %{ctor: "Square", fields: [%{label: "side", type: "f64"}]}
    ]
  }
]

func = %{
  name: "area",
  param_name: "shape",
  param_type: "Shape",
  param_cap: :iso,
  ret: "f64",
  clauses: [
    %{pats: [{:ctor, "Circle", [{:var, "r"}]}], body: "pi * r * r"},
    %{pats: [{:ctor, "Square", [{:var, "s"}]}], body: "s * s"}
  ]
}

out = Lower.compile(types, func)

IO.puts("===== RIAN SOURCE =====")
IO.puts("""
type Shape := Circle(radius f64) | Square(side f64)

fn area(Shape) f64
fn area(Circle(r)) := pi * r * r
fn area(Square(s)) := s * s
""")

IO.puts("===== EMITTED ELIXIR =====")
IO.puts(out.elixir)

IO.puts("\n===== EMITTED RUST =====")
IO.puts(out.rust)

# --- execute the emitted Elixir to prove correctness ---
IO.puts("\n===== EXECUTE EMITTED ELIXIR =====")
Code.eval_string("defmodule AreaGen do\n#{out.elixir}\nend")
a = apply(AreaGen, :area, [{:circle, 2.0}])
b = apply(AreaGen, :area, [{:square, 3.0}])
:io.format("area(circle 2.0) = ~p   area(square 3.0) = ~p~n", [a, b])
IO.puts(if abs(a - :math.pi() * 4) < 1.0e-9 and b == 9.0, do: "ELIXIR OK", else: "ELIXIR WRONG")

# --- write the emitted Rust to disk for rustc ---
File.write!("area_gen.rs", "#![allow(dead_code)]\n" <> out.rust <> """


fn main() {
    let a = area(Shape::Circle { radius: 2.0 });
    let b = area(Shape::Square { side: 3.0 });
    assert!((a - std::f64::consts::PI * 4.0).abs() < 1e-9);
    assert!((b - 9.0).abs() < 1e-9);
    println!("area(circle 2.0) = {}   area(square 3.0) = {}", a, b);
}
""")

# --- exhaustiveness GATE demonstration ---
IO.puts("\n===== EXHAUSTIVENESS GATE (missing Square) =====")
bad = %{func | clauses: [hd(func.clauses)]}

try do
  Lower.compile(types, bad)
  IO.puts("ERROR: should have refused to emit")
rescue
  e -> IO.puts("refused to emit -> #{Exception.message(e)}")
end

# --- expression-lowering gallery (operator table -> both targets) ---
IO.puts("\n===== EXPRESSION LOWERING GALLERY =====")
exprs = ["a + b * c", "n div 2", "a / b", "x |> f(y) |> g", "s <> t <> u", "a and not b"]

Enum.each(exprs, fn s ->
  el = Rian.Lower.emit_expr(s, :elixir)
  rs = Rian.Lower.emit_expr(s, :rust)
  :io.format("~-16s | elixir: ~-26s | rust: ~s~n", [s, el, rs])
end)

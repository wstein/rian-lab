alias Rian.Capability, as: C
alias Rian.Lower
alias Rian.Pratt

IO.puts("===== CAPABILITY -> RUST PARAMETER TYPE =====")
types_demo = ["Int64", "Float64", "String", "Vec(Float64)", "Shape"]

for cap <- [:val, :iso, :ref, :tag] do
  row = Enum.map_join(types_demo, "  |  ", fn t -> "#{t}: #{C.rust_param(cap, t)}" end)
  :io.format("~-4s  ~s~n", [cap, row])
end

# Prove every emitted signature is valid Rust by compiling them.
sig = fn name, ty -> "fn #{name}(x: #{ty}) {}" end

rust_sigs =
  [
    {"v_i64", C.rust_param(:val, "Int64")},
    {"v_str", C.rust_param(:val, "String")},
    {"v_vec", C.rust_param(:val, "Vec(Float64)")},
    {"i_str", C.rust_param(:iso, "String")},
    {"i_vec", C.rust_param(:iso, "Vec(Float64)")},
    {"r_i64", C.rust_param(:ref, "Int64")},
    {"r_str", C.rust_param(:ref, "String")}
  ]
  |> Enum.map_join("\n", fn {n, t} -> sig.(n, t) end)

File.write!("cap_sigs.rs", "#![allow(dead_code)]\n" <> rust_sigs <> "\nfn main() {}\n")

IO.puts("\n===== area WITH `val Shape` (capability-driven signature) =====")

types = [
  %{
    name: "Shape",
    variants: [
      %{ctor: "Circle", fields: [%{label: "radius", type: "Float64"}]},
      %{ctor: "Square", fields: [%{label: "side", type: "Float64"}]}
    ]
  }
]

area = %{
  name: "area",
  params: [%{name: "shape", type: "Shape", cap: :val}],
  ret: "Float64",
  clauses: [
    %{pats: [{:ctor, "Circle", [{:var, "r"}]}], body: "pi * r * r"},
    %{pats: [{:ctor, "Square", [{:var, "s"}]}], body: "s * s"}
  ]
}

out = Lower.compile(types, area)
IO.puts(out.rust)

File.write!("area_cap.rs", "#![allow(dead_code)]\n" <> out.rust <> """


fn main() {
    let a = area(&Shape::Circle { radius: 2.0 });
    let b = area(&Shape::Square { side: 3.0 });
    assert!((a - std::f64::consts::PI * 4.0).abs() < 1e-9);
    assert!((b - 9.0).abs() < 1e-9);
    println!("rust(&Shape) area(circle 2.0)={} area(square 3.0)={}", a, b);
}
""")

IO.puts("\n===== BEAM LINEARITY (use-once) =====")
env = %{"f" => :iso}

cases = [
  {"use(f)", "iso used once"},
  {"pair(f, f)", "iso used twice"},
  {"len(xs)", "(xs is val) — n/a"}
]

for {body, label} <- cases do
  res = C.lin_check(env, Pratt.parse(body))
  :io.format("~-14s (~s) => ~p~n", [body, label, res])
end

# val parameter may be used many times (this is why `area`'s r*r is fine)
:io.format("~-14s (val used twice)   => ~p~n",
  ["pi * r * r", C.lin_check(%{"r" => :val}, Pratt.parse("pi * r * r"))])

# block form: f consumed once across two bindings is fine; twice is an error
ok_block = C.lin_check_block(%{"f" => :iso}, [{"b", :val, Pratt.parse("read(f)")}], Pratt.parse("b"))
bad_block =
  C.lin_check_block(
    %{"f" => :iso},
    [{"x", :val, Pratt.parse("read(f)")}, {"y", :val, Pratt.parse("read(f)")}],
    Pratt.parse("0")
  )

:io.format("block consume-once  => ~p~n", [ok_block])
:io.format("block consume-twice => ~p~n", [bad_block])

IO.puts("\n===== `ref` ON THE BEAM TARGET =====")
ref_func = %{area | params: [%{hd(area.params) | cap: :ref}]}

try do
  Lower.to_elixir(ref_func, types)
  IO.puts("ERROR: should have rejected ref")
rescue
  e -> IO.puts("rejected -> #{Exception.message(e)}")
end

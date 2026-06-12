alias Rian.Lower

# Each function relies on TARGET libraries via FFI — no Rian stdlib.
funcs = [
  # Rian:  fn total(xs val Vec(i64)) i64 := :lists.sum(xs)
  {%{name: "total", param_name: "xs", param_type: "Vec(Int64)", param_cap: :val, ret: "Int64",
     clauses: [%{pats: [{:var, "xs"}], body: ":lists.sum(xs)"}]},
   [[1, 2, 3, 4]], 10},

  # Rian:  fn rev(xs val Vec(i64)) Vec(i64) := :lists.reverse(xs)
  {%{name: "rev", param_name: "xs", param_type: "Vec(Int64)", param_cap: :val, ret: "Vec(Int64)",
     clauses: [%{pats: [{:var, "xs"}], body: ":lists.reverse(xs)"}]},
   [[1, 2, 3]], [3, 2, 1]},

  # Rian:  fn shout(s val str) str := String.upcase(s)         (Elixir lib)
  {%{name: "shout", param_name: "s", param_type: "String", param_cap: :val, ret: "String",
     clauses: [%{pats: [{:var, "s"}], body: "String.upcase(s)"}]},
   ["hi"], "HI"},

  # Rian:  fn clean(s val str) str := String.trim(String.downcase(s))   (nested FFI)
  {%{name: "clean", param_name: "s", param_type: "String", param_cap: :val, ret: "String",
     clauses: [%{pats: [{:var, "s"}], body: "String.trim(String.downcase(s))"}]},
   ["  HeLLo  "], "hello"}
]

IO.puts("===== RIAN -> ELIXIR (FFI to target libs) =====")

emitted =
  Enum.map(funcs, fn {f, _args, _exp} ->
    # FFI is BEAM-only, so compile to the BEAM target (not Rust).
    el = Lower.compile_beam([], f).elixir |> String.split("\n") |> List.last()
    IO.puts(el)
    {f.name, el}
  end)

# Build one module from all clauses and execute
body = Enum.map_join(emitted, "\n", fn {_n, el} -> el end)
Code.eval_string("defmodule Ffi do\n#{body}\nend")

IO.puts("\n===== EXECUTE ON THE BEAM =====")

Enum.each(funcs, fn {f, args, expected} ->
  got = apply(Ffi, String.to_atom(f.name), args)
  ok = if got == expected, do: "OK", else: "WRONG (expected #{inspect(expected)})"
  :io.format("~-7s ~p => ~p   ~s~n", [f.name, args, got, ok])
end)

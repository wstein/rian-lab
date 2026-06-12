alias Rian.Decl

# Stage 0.1: read a real `.rian` source FILE, parse its declarations, and lower
# them to both targets — then run the BEAM output to prove it.
path = "examples/area.rian"
src = File.read!(path)

IO.puts("===== SOURCE (#{path}) =====")
IO.puts(src)

[{_name, out}] = Decl.compile(src)

IO.puts("===== EMITTED ELIXIR =====")
IO.puts(out.elixir)

IO.puts("\n===== EMITTED RUST =====")
IO.puts(out.rust)

Code.eval_string("defmodule AreaFile do\n#{out.elixir}\nend")

IO.puts("\n===== EXECUTE ON THE BEAM =====")
a = AreaFile.area({:circle, 2.0})
b = AreaFile.area({:square, 3.0})
:io.format("area(circle 2.0) = ~p   area(square 3.0) = ~p~n", [a, b])
IO.puts(if abs(a - :math.pi() * 4) < 1.0e-9 and b == 9.0, do: "OK", else: "WRONG")

# The exhaustiveness gate runs on parsed source too: drop a clause and emission
# is refused.
IO.puts("\n===== EXHAUSTIVENESS GATE (drop the Square clause) =====")
bad = String.replace(src, "def area(Square(s)) := s * s\n", "")

try do
  Decl.compile(bad)
  IO.puts("ERROR: should have refused to emit")
rescue
  e -> IO.puts("refused to emit -> #{Exception.message(e)}")
end

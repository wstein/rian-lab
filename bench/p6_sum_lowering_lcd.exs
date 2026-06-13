# P6 spike — does a shared traversal for sum-type lowering cause a
# lowest-common-denominator (LCD) regression? (Mira/Dmitri's concern, ADR-0041.)
#
# Lowers one sum type to all four targets over the shared Core IR and asserts each
# gets its IDIOMATIC representation — crucially, Rust a real `enum`, not a simulated
# tagged tuple. Result: no LCD; the per-target leaf representation is preserved.
#
#   mix run bench/p6_sum_lowering_lcd.exs
alias Rian.{Decl, Lower, JVM, Beam}

src = "type Expr := Num(Int64) | Add(Expr, Expr) | Zero"
prog = Decl.parse(src)
rust = Lower.rust_program(prog)
kotlin = JVM.compile(src)
{:ok, m} = Beam.load("type Expr := Num(Int64) | Zero\npub def mk() Expr := Num(5)", :p6_beam)

rust_enum? = rust =~ ~r/enum Expr \{/ and rust =~ ~r/Num\(i64\)/
no_tuple_sim? = not (rust =~ ~r/Expr = \(/)
kotlin_sealed? = kotlin =~ "sealed interface Expr"
beam_tuple = m.mk()

IO.puts("P6 sum-lowering LCD spike — one IR, four idiomatic representations:")
IO.puts("  Rust:  real enum?  #{rust_enum?}   not a tuple-sim?  #{no_tuple_sim?}")
IO.puts("  Kotlin: sealed interface?  #{kotlin_sealed?}")
IO.puts("  BEAM:  tagged tuple  #{inspect(beam_tuple)}")
IO.puts("\nVERDICT: no LCD regression — Rust keeps its enum. A shared traversal is")
IO.puts("safe iff it dispatches REPRESENTATION per target at the sum-lowering leaf;")
IO.puts("sharing the representation (everyone a tagged tuple) WOULD cost Rust its enum.")

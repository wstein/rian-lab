defmodule RianLab do
  @moduledoc """
  RianLab — the reference implementation and design corpus for **Rian**.

  Rian is a typed, capability-disciplined language hosted on the Erlang/BEAM
  ecosystem. The same source lowers to two targets:

    * **BEAM** — idiomatic Elixir/Erlang (tagged tuples, multi-clause `def`,
      guards), reusing OTP and the Hex ecosystem (no fork — see ADR-0026).
    * **Rust** — idiomatic ownership-checked code, where Rian's *reference
      capabilities* (`val`/`iso`/`ref`/`tag`) drive borrow-vs-own signatures
      with no lifetime annotations (see `docs/spec/capability-lowering.md`).

  This project hosts the compiler front-end and lowering passes. The pipeline is:

      parse (Pratt)
        → pattern lowering
        → exhaustiveness gate   # refuses to emit on a non-total / dead match
        → macro / comptime expansion
        → emit Elixir | emit Rust

  See `docs/README.md` for the full map of architecture decisions (ADRs) and
  language specifications.

  ## Module map

    * `Rian.Pratt` — precedence-climbing expression parser
    * `Rian.Exhaustiveness` — Maranget usefulness algorithm (the emission gate)
    * `Rian.PatternLower` — surface patterns → checker IR
    * `Rian.Capability` — capability → Rust signature + BEAM linearity
    * `Rian.Lower` — end-to-end lowering to Elixir and Rust
    * `Rian.Macro` / `Rian.Comptime` — hygienic macros and pure comptime
  """

  @doc "The current RianLab version, read from the project config."
  @spec version() :: String.t()
  def version, do: Application.spec(:rian_lab, :vsn) |> to_string()
end

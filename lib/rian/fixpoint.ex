defmodule Rian.Fixpoint do
  @moduledoc """
  Self-hosting verification harness (ADR-0027/0031) — turns a Rian-written lexer
  from a *demo* into a *regression test*.

  The spike proved a lexer written in Rian compiles to real `.beam` and runs
  (`compiler/lexer.rian`, SELFHOST.md). This harness adds the
  missing half: it runs that compiled lexer over a corpus and **diffs its token
  stream against the reference `Rian.Lexer`** — the Elixir tokenizer the rest of
  the toolchain trusts. Drift in *either* lexer (the Rian source or the
  reference) now fails the diff, so the equivalence is checked, not assumed.

  A Rian lexer emits its **own** `Token` sum, lowered to tagged tuples/atoms
  (`TNum(n)` → `{:t_num, n}`, `TPlus` → `:t_plus`, …), so it cannot be compared
  to `Rian.Lexer`'s tokens term-for-term. The caller supplies a `project`
  function mapping each Rian token to the reference token shape; over the shared
  input domain the projected streams must be **identical**.

  This is the verification step the real-lexer port (the next self-hosting move)
  plugs into: replace the corpus/projection as the Rian lexer grows toward the
  full Rian token vocabulary, and the harness keeps proving agreement.
  """
  alias Rian.Beam

  @typedoc "A loaded BEAM module exposing `tokenize/1` (a compiled Rian lexer)."
  @type lexer_mod :: module()

  @doc """
  Compile a Rian lexer `source` (a module with a `pub tokenize/1`) to real
  bytecode under `mod`, returning the loaded module or raising on failure.
  """
  @spec load_lexer(String.t(), atom()) :: lexer_mod()
  def load_lexer(source, mod) do
    {:ok, ^mod} = Beam.load(source, mod)
    mod
  end

  @doc """
  For each `input` in `corpus`, compare the Rian lexer's projected output against
  the `reference` tokenizer (default `Rian.Lexer.expr_tokens/1`; pass
  `&Rian.Lexer.tokenize/1` to check the full declaration stream incl. `{:nl}`).
  Returns `:ok`, or the first `{:mismatch, input, expected, got}` so the failing
  case is reported precisely.

  `project` maps one Rian token (tagged tuple/atom) to its reference-token shape.
  """
  @spec check(lexer_mod(), [String.t()], (term() -> term()), (String.t() -> [term()])) ::
          :ok | {:mismatch, String.t(), [term()], [term()]}
  def check(mod, corpus, project, reference \\ &Rian.Lexer.expr_tokens/1) do
    Enum.reduce_while(corpus, :ok, fn input, _acc ->
      expected = reference.(input)
      got = mod.tokenize(input) |> Enum.map(project)

      if got == expected,
        do: {:cont, :ok},
        else: {:halt, {:mismatch, input, expected, got}}
    end)
  end
end

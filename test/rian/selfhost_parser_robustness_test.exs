defmodule Rian.SelfhostParserRobustnessTest do
  # async: false — the runtime teeth load the Rian-written parser into the VM.
  use ExUnit.Case, async: false

  alias Rian.{Beam, Core, Exhaustiveness, PatternLower, Pratt}

  # The self-hosted parser used to assume well-formed input: every
  # `case parse_X(...) do <expected-continuation> -> ... end` had no arm for a
  # malformed continuation, so a missing `do`/`->`/`end` crashed the parser with a
  # raw `CaseClauseError` instead of producing a parse error. The `case`-body
  # exhaustiveness gate (`Rian.Exhaustiveness.check_case_bodies!`) flagged these as
  # non-exhaustive; the fix threads the established in-band `EErr` sentinel through
  # each parser `case` (and an explicit `ArmErr` so the arm loop terminates).
  #
  # This file is the proof, on the ACTIVE self-hosted compiler — the verified parser
  # (`compiler/decl.rian`) and the final driver (`compiler/compose_real_sum.rian`):
  #   1. STRUCTURAL — both files are `case`-exhaustive (the gate finds nothing).
  #   2. RUNTIME    — the parser, loaded onto the BEAM, turns malformed input into an
  #                   `EErr` node instead of crashing.

  @active [
    {"decl.rian (the verified parser)", "compiler/decl.rian"},
    {"compose_real_sum.rian (the final driver)", "compiler/compose_real_sum.rian"}
  ]

  # every `case` reachable from a function body, via the same Core walk the gate uses.
  defp cases(%Core.ECase{} = n, acc), do: kids(n, [n | acc])
  defp cases(n, acc) when is_struct(n), do: kids(n, acc)
  defp cases(l, acc) when is_list(l), do: Enum.reduce(l, acc, &cases/2)
  defp cases(t, acc) when is_tuple(t), do: t |> Tuple.to_list() |> Enum.reduce(acc, &cases/2)
  defp cases(_, acc), do: acc
  defp kids(s, acc), do: s |> Map.from_struct() |> Map.values() |> Enum.reduce(acc, &cases/2)

  defp non_exhaustive_cases(path) do
    prog = Rian.Decl.parse(File.read!(path))

    for m <- Map.get(prog, :mods, []),
        env =
          Exhaustiveness.program_env(
            Map.get(m, :types, []),
            Map.get(m, :structs, []),
            Map.get(m, :ranges, [])
          ),
        func <- m.funcs,
        clause <- func.clauses,
        is_binary(clause.body),
        core = body_core(clause.body),
        core != nil,
        c <- cases(core, []),
        rows =
          Enum.map(c.arms, fn {p, g, _} ->
            PatternLower.lower_clause(%{pats: [p], guard: g != nil}, env)
          end),
        r = Exhaustiveness.analyze(rows, 1, env),
        not r.exhaustive? do
      "#{func.name}: missing `#{Exhaustiveness.render(r.missing)}`"
    end
  end

  defp body_core(body) do
    Core.from_expr(Pratt.parse_body(body))
  rescue
    _ -> nil
  end

  describe "structural — the active self-hosted compiler is `case`-exhaustive" do
    for {label, path} <- @active do
      @path path
      test "#{label} has no non-exhaustive `case`" do
        assert non_exhaustive_cases(@path) == [],
               "#{@path} has non-exhaustive `case`(s): #{inspect(non_exhaustive_cases(@path))}"
      end
    end
  end

  setup_all do
    {:ok, _} = Beam.load(File.read!("compiler/lexer_v2.rian"), :"Elixir.LexerV2")
    {:ok, _} = Beam.load(File.read!("compiler/decl.rian"), :"Elixir.Decl")
    :ok
  end

  describe "runtime — malformed input yields `EErr`, never a `CaseClauseError`" do
    # each program is malformed at exactly one parser `case` whose missing arm the fix
    # added: a function body that reaches `parse_if`/`parse_if_then`/`parse_if_else`/
    # `parse_case`/`parse_arm`/`parse_with` with the wrong continuation token.
    @malformed [
      {"if without `do`", "pub def f(c Bool) Int53 := if c bad 1 else 2 end"},
      {"if without `else`", "pub def f(c Bool) Int53 := if c do 1 bad 2 end"},
      {"if without `end`", "pub def f(c Bool) Int53 := if c do 1 else 2 bad"},
      {"case without `do`", "pub def f(c Bool) Int53 := case c bad A -> 1 end"},
      {"arm without `->`", "pub def f(c Bool) Int53 := case c do\n  A bad 1\nend"},
      {"with without `do`", "pub def f(c Bool) Int53 := with x <- c bad 1 end"}
    ]

    for {label, src} <- @malformed do
      @src src
      test "#{label} parses to an `EErr` node, no crash" do
        toks = :"Elixir.LexerV2".tokenize(@src)

        # the property: parse_program returns (does NOT raise CaseClauseError) and the
        # malformed body surfaces the in-band `:e_err` sentinel.
        result = :"Elixir.Decl".parse_program(toks)
        assert inspect(result, limit: :infinity) =~ "e_err"
      end
    end
  end
end

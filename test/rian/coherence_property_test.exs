defmodule Rian.CoherencePropertyTest do
  @moduledoc """
  Seeded generative checks for `Rian.Coherence` (ADR-0061 §5 / ADR-0087 §5).

  A reproducible `:rand` generator (fixed `@seed`, so any failure reproduces)
  builds random `protocol`/`impl` programs and asserts the coherence gate's
  invariants hold for *every* one: a coherent program parses, and a program with
  a planted violation is rejected with the matching rule. This is the property
  form of the hand-picked cases in `protocol_test.exs` — it varies the protocol
  set, the impl types, and their order to catch combination/ordering bugs a fixed
  corpus would miss.
  """
  use ExUnit.Case, async: true

  alias Rian.{Coherence, Decl}
  alias Rian.Coherence.Error, as: CoherenceError

  # ADR-0061; any value reproduces the same sequence on re-run.
  @seed {0xC0, 0xFFEE, 0x61}
  @runs 200

  # impl types whose BEAM dispatch guards are pairwise DISTINCT — so any set of
  # them dispatches unambiguously (a coherent program). `Int64` covers the
  # integer guard; `Char` (also `is_integer`) is reserved for the shared-guard
  # case and never mixed in here.
  @distinct_guard ~w(Bool String Float64 Int64)
  @protos ~w(P Q R)

  setup do
    :rand.seed(:exsss, @seed)
    :ok
  end

  # each protocol gets a distinct method name (`mp`/`mq`/`mr`) so a coherent
  # multi-protocol program does not collide two dispatchers on one method name —
  # an orthogonal concern to coherence.
  defp mname(p), do: "m" <> String.downcase(p)
  defp proto_src(p), do: "protocol #{p} do\n  def #{mname(p)}(self Self) Bool\nend\n"
  defp impl_src(p, t), do: "impl #{p} for #{t} do\n  def #{mname(p)}(x) := true\nend\n"

  defp subset(list), do: list |> Enum.shuffle() |> Enum.take(:rand.uniform(length(list)))

  # a coherent program: each chosen protocol gets one impl over each of a
  # distinct-guard subset of types. Returns `{source, [{proto, type}]}`.
  defp gen_coherent do
    pairs =
      for p <- subset(@protos), t <- subset(@distinct_guard), do: {p, t}

    protos = pairs |> Enum.map(&elem(&1, 0)) |> Enum.uniq()
    decls = Enum.map(protos, &proto_src/1) ++ Enum.map(pairs, fn {p, t} -> impl_src(p, t) end)
    {Enum.join(Enum.shuffle(decls), "\n"), pairs}
  end

  describe "coherent programs parse (no false positives)" do
    test "a randomly generated coherent program parses with all impls collected" do
      for _ <- 1..@runs do
        {src, pairs} = gen_coherent()
        prog = Decl.parse(src)
        assert MapSet.new(prog.impls) == MapSet.new(pairs)
        assert Coherence.violations(protocols_of(src), impls_of(pairs), reg(), nil) == []
      end
    end
  end

  describe "planted violations are rejected with the matching rule" do
    test "a duplicate `(protocol, type)` is rejected" do
      for _ <- 1..@runs do
        {src, pairs} = gen_coherent()
        {p, t} = Enum.random(pairs)

        assert_raise CoherenceError, ~r/duplicate `impl #{p} for #{t}`/, fn ->
          Decl.parse(src <> "\n" <> impl_src(p, t))
        end
      end
    end

    test "an impl whose method set differs from the protocol is rejected" do
      for _ <- 1..@runs do
        p = Enum.random(@protos)
        t = Enum.random(@distinct_guard)
        src = proto_src(p) <> "impl #{p} for #{t} do\n  def wrong(x) := true\nend\n"
        assert_raise CoherenceError, ~r/does not match the protocol/, fn -> Decl.parse(src) end
      end
    end

    test "two impls sharing a runtime discriminator are rejected on a runtime-dispatch target" do
      for _ <- 1..@runs do
        p = Enum.random(@protos)
        # `Int64` and `Char` both guard `is_integer` — ambiguous where dispatch is
        # by runtime shape (the unannotated default reaches `:ex`).
        src = proto_src(p) <> impl_src(p, "Int64") <> impl_src(p, "Char")
        assert_raise CoherenceError, ~r/ambiguous dispatch/, fn -> Decl.parse(src) end
      end
    end

    test "the same shared-discriminator pair is accepted on a Rust-only module" do
      for _ <- 1..@runs do
        p = Enum.random(@protos)

        src = """
        @targets(rs)
        mod M do
          #{proto_src(p)}
          #{impl_src(p, "Int64")}
          #{impl_src(p, "Char")}
        end
        """

        # static Rust types `i64`/`char` are distinct, so the rule does not apply.
        assert [_ | _] = Decl.compile(src)
      end
    end

    test "an impl for a type with no runtime discriminator (a type variable) is rejected" do
      for _ <- 1..@runs do
        p = Enum.random(@protos)
        src = proto_src(p) <> impl_src(p, "T")

        assert_raise CoherenceError, ~r/no runtime discriminator for `T`/, fn ->
          Decl.parse(src)
        end
      end
    end
  end

  describe "violations/4 (the structured pure API the Check gate consumes)" do
    test "returns one tagged violation per rule, not a raise" do
      protocols = %{"P" => [%{name: "m", params: "self Self", ret: "Bool"}]}

      dup = [impl("P", "Int64"), impl("P", "Int64")]

      assert [%{rule: :duplicate, proto: "P", type: "Int64"}] =
               Coherence.violations(protocols, dup, reg(), nil)

      shared = [impl("P", "Int64"), impl("P", "Char")]

      assert [%{rule: :shared_discriminator}] =
               Coherence.violations(protocols, shared, reg(), [:ex])

      # …and exempt on a Rust-only target set.
      assert Coherence.violations(protocols, shared, reg(), [:rs]) == []

      unknown = [impl("Nope", "Int64")]

      assert [%{rule: :unknown_protocol, proto: "Nope"}] =
               Coherence.violations(protocols, unknown, reg(), nil)
    end
  end

  # ── tiny builders mirroring the per-scope inputs `expand` passes ─────────────
  defp reg, do: Coherence.registry([], [])

  defp impl(proto, type),
    do: {proto, type, [%{name: "m", params: "x", guard: nil, body: "true"}], %{}}

  defp protocols_of(_src),
    do: Map.new(@protos, &{&1, [%{name: mname(&1), params: "self Self", ret: "Bool"}]})

  defp impls_of(pairs),
    do:
      Enum.map(pairs, fn {p, t} ->
        {p, t, [%{name: mname(p), params: "x", guard: nil, body: "true"}], %{}}
      end)
end

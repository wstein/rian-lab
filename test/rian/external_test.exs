defmodule Rian.ExternalTest do
  @moduledoc """
  `@external(:target, "spec")` — target-scoped FFI bodies (ADR-0068). A bodiless
  `def` with one-or-more per-target host bodies; the signature is checked once,
  `Rian.Reach` reads the externals for an honest target set, and each emitter
  lowers its target's spec.
  """
  use ExUnit.Case, async: false

  alias Rian.{Decl, Reach}

  describe "parsing (ADR-0068 §1)" do
    test "one-or-more `@external` attrs attach a per-target body map to a bodiless def" do
      # NB: specs are quote-free here — embedded `"` in a spec needs lexer escape
      # support (a separate gap; see the spawned task). The feature itself is agnostic.
      prog =
        Decl.parse(~S|@external(:ex, ":erlang.float_to_list(x, [{:decimals, 6}])")
        @external(:js, "x.toFixed(6)")
        @external(:rs, "x.to_string()")
        def format6(x val Float64) String|)

      f = hd(prog.funcs)
      assert f.name == "format6"
      assert f.clauses == []

      assert f.externals == %{
               ex: ":erlang.float_to_list(x, [{:decimals, 6}])",
               js: "x.toFixed(6)",
               rs: "x.to_string()"
             }

      assert [%{name: "x", type: "Float64", cap: :val}] = f.params
    end

    test "a single-target `@external` is fine (reaches exactly that target)" do
      f = hd(Decl.parse(~S|@external(:ex, ":os.system_time()") def now() Int64|).funcs)
      assert f.externals == %{ex: ":os.system_time()"}
    end

    test "`@external` plus a portable body for the function is rejected" do
      assert_raise Decl.Error, ~r/cannot accompany a portable body/, fn ->
        Decl.parse(~S|@external(:ex, ":x") def f() String := "hi"|)
      end
    end

    test "two `@external`s for the same target are rejected" do
      assert_raise Decl.Error, ~r/duplicate `@external/, fn ->
        Decl.parse("@external(:ex, \"a\")\n@external(:ex, \"b\")\ndef f() String")
      end
    end

    test "`@external` must precede a `def`, and the target must be known" do
      assert_raise Decl.Error, ~r/may only precede a `def`/, fn ->
        Decl.parse(~S|@external(:ex, "a") type T := A|)
      end

      assert_raise Decl.Error, ~r/unknown target `:wasm`/, fn ->
        Decl.parse(~S|@external(:wasm, "a") def f() String|)
      end
    end
  end

  describe "reach (ADR-0068 §2)" do
    test "the reachable set is exactly the declared `@external` targets" do
      rep =
        Reach.analyze(Decl.parse(~S|@external(:ex, "a")
          @external(:js, "b")
          @external(:rs, "c")
          def format6(x val Float64) String|))

      assert targets(rep, "format6") == [:ex, :js, :rs]
    end

    test "a single-target external is honestly pinned to that target" do
      rep = Reach.analyze(Decl.parse(~S|@external(:ex, ":os.system_time()") def now() Int64|))
      assert targets(rep, "now") == [:ex]
    end

    test "an external function in a `@targets` module is gated against its coverage" do
      # `@external(:ex)` only -> reaches [:ex]; a `@targets(ex, js)` module then
      # fails the contract because `js` has no body (ADR-0058 gate over ADR-0068).
      src = ~S|@targets(ex, js)
      mod M do
        @external(:ex, ":os.system_time()")
        pub def now() Int64
      end|

      assert {:error, msg} = Reach.check_contracts(Decl.parse(src))
      assert msg =~ "now cannot reach [:js]"
    end
  end

  defp targets(rep, name), do: rep[name][:reach] |> MapSet.to_list() |> Enum.sort()
end

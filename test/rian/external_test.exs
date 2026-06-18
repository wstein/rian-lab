defmodule Rian.ExternalTest do
  @moduledoc """
  `@external(:target, "spec")` — target-scoped FFI bodies (ADR-0068). A bodiless
  `def` with one-or-more per-target host bodies; the signature is checked once,
  `Rian.Reach` reads the externals for an honest target set, and each emitter
  lowers its target's spec.
  """
  use ExUnit.Case, async: false

  alias Rian.{Check, Decl, External, Reach}

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

  # `Reach.entry/2` resolves a bare name against the `"name/arity"`-keyed report.
  defp targets(rep, name), do: Reach.entry(rep, name)[:reach] |> MapSet.to_list() |> Enum.sort()

  describe "check (ADR-0068 §3 — signature only, val/tag params)" do
    test "a `val`/`tag` external passes the type gate (the body is trusted FFI)" do
      assert Check.gate!(Decl.parse(~S|@external(:ex, ":os.system_time()") def now() Int64|)) ==
               :ok

      assert Check.gate!(Decl.parse(~S|@external(:ex, ":f.g(x)") def f(x tag Vec(Int64)) Int64|)) ==
               :ok
    end

    test "an `iso`/`ref` external parameter is rejected (linearity not enforceable over FFI)" do
      for cap <- ~w(iso ref) do
        assert_raise Check.Error, ~r/must be `val` or `tag`/, fn ->
          Check.gate!(Decl.parse(~s|@external(:ex, ":f.g(x)") def f(x #{cap} Int64) Int64|))
        end
      end
    end
  end

  describe "emit (ADR-0068 §3 — each emitter lowers its target's spec)" do
    test "BEAM: the `:ex` spec runs as the function body" do
      {:ok, mod} =
        Rian.Beam.load(
          ~S|@external(:ex, ":erlang.float_to_list(x, [{:decimals, 2}])") pub def fmt(x val Float64) String|,
          :"rian_ext_#{System.unique_integer([:positive])}"
        )

      assert apply(mod, :fmt, [3.14159]) == ~c"3.14"
    end

    test "JS: the `:js` spec is emitted verbatim with params bound, and runs under node" do
      js = Rian.JS.compile(~S|@external(:js, "x + 1") pub def inc(x val Int53) Int53|)
      assert js =~ "function inc(a0) { const x = a0; return (x + 1); }"

      case node_run(js, "inc(41)") do
        :no_node -> :ok
        out -> assert out == "42"
      end
    end

    test "Rust: the `:rs` spec is the function body (params named directly)" do
      rust =
        Rian.Lower.rust_program(
          Decl.parse(~S|@external(:rs, "x.abs()") pub def mag(x val Int64) Int64|)
        )

      assert rust =~ "fn mag(x: i64) -> i64 { x.abs() }"
    end

    test "JVM: the `:jvm` spec is emitted with params bound" do
      kt = Rian.JVM.compile(~S|@external(:jvm, "Math.abs(x)") pub def mag(x val Int64) Int64|)
      assert kt =~ "fun mag(a0: Long): Long { val x = a0; return Math.abs(x) }"
    end

    test "an emitter asked for a target the function has no body for raises (ADR-0041 §2)" do
      # `inc` has only an `:ex` body -> off `:js`; compiling it to JS is an error,
      # never a silent stub. (Reach pins it off `:js` so this can't arise after a gate.)
      assert_raise Rian.JS.Unsupported, ~r/no `@external\(:js/, fn ->
        Rian.JS.compile(~S|@external(:ex, ":os.system_time()") pub def inc() Int64|)
      end
    end
  end

  describe "reference form `@external(:t, Mod.fun)` (ADR-0068 / ADR-0081)" do
    test "an erlang reference parses to a tagged ref and lowers to a positional call" do
      f =
        hd(
          Decl.parse(~S|@external(:ex, :erlang.binary_to_list) pub def to_list(s String) _Unk|).funcs
        )

      assert f.externals == %{ex: {:ref, ["erlang", "binary_to_list"], true}}
      # the reference renders to the same host call a string spec would (params positional)
      assert Rian.External.render(f.externals.ex, f.params) == ":erlang.binary_to_list(s)"
    end

    test "a dotted Elixir/Rian reference lowers to `Mod.fun(args)`" do
      f =
        hd(
          Decl.parse(
            ~S|@external(:ex, Rian.Beam.load_result) pub def lr(s String, m Symbol) _Unk|
          ).funcs
        )

      assert f.externals == %{ex: {:ref, ["Rian", "Beam", "load_result"], false}}
      assert Rian.External.render(f.externals.ex, f.params) == "Rian.Beam.load_result(s, m)"
    end

    test "a reference to a non-existent host function/arity is a compile error (no silent stub)" do
      bad = ~S|@external(:ex, :erlang.no_such_fun_xyz) pub def b(s String) _Unk|
      {:error, msg} = Check.check(bad)
      assert msg =~ "no `no_such_fun_xyz/1` is exported"
    end

    test "a resolvable erlang reference passes the check; the string form still works" do
      assert Check.check(~S|@external(:ex, :erlang.binary_to_list) pub def t(s String) _Unk|) ==
               :ok

      assert Check.check(~S|@external(:ex, ":erlang.binary_to_list(s)") pub def t(s String) _Unk|) ==
               :ok
    end

    test "Reach reads the target set identically for a reference (spec form is irrelevant)" do
      rep =
        Decl.parse(~S|@external(:ex, :erlang.binary_to_list) pub def t(s String) _Unk|)
        |> Reach.analyze()

      assert Reach.entry(rep, "t").reach |> MapSet.to_list() == [:ex]
    end

    test "the file-reference form parses to a `{:file, path, fun}` spec (ADR-0080 §7)" do
      prog = Decl.parse(~S|@external(:js, "./ffi.mjs", "fun") pub def f(x Int53) Int53|)
      [f] = prog.funcs
      assert f.externals == %{js: {:file, "./ffi.mjs", "fun"}}
    end
  end

  describe "file-reference resolution (ADR-0080 §7 a/c)" do
    setup do
      dir = Path.join(System.tmp_dir!(), "rian_ffi_#{System.unique_integer([:positive])}")
      File.mkdir_p!(dir)
      on_exit(fn -> File.rm_rf(dir) end)
      {:ok, dir: dir}
    end

    test "a program with no file-references resolves trivially", %{dir: dir} do
      prog = Decl.parse(~S|@external(:ex, :erlang.length) pub def f(x _Unk) Int53|)
      assert External.resolve(prog, dir) == :ok
    end

    test "fails closed when the referenced file is missing", %{dir: dir} do
      prog = Decl.parse(~S|@external(:js, "./missing.ffi.mjs", "fun") pub def f(x Int53) Int53|)
      assert {:error, msg} = External.resolve(prog, dir)
      assert msg =~ "missing.ffi.mjs"
      assert msg =~ "does not exist"
    end

    test "a non-Elixir file is existence-checked only and resolves when present", %{dir: dir} do
      File.write!(Path.join(dir, "codec.ffi.mjs"), "export function encode(x) { return x }\n")
      prog = Decl.parse(~S|@external(:js, "./codec.ffi.mjs", "encode") pub def f(x Int53) Int53|)
      assert External.resolve(prog, dir) == :ok
    end

    test "an Elixir file must export the named function at the right arity", %{dir: dir} do
      File.write!(
        Path.join(dir, "codec.ffi.ex"),
        "defmodule Codec do\n  def enc(x), do: x\nend\n"
      )

      ok = Decl.parse(~S|@external(:ex, "./codec.ffi.ex", "enc") pub def f(x Int53) Int53|)
      assert External.resolve(ok, dir) == :ok

      bad_name = Decl.parse(~S|@external(:ex, "./codec.ffi.ex", "nope") pub def f(x Int53) Int53|)
      assert {:error, msg} = External.resolve(bad_name, dir)
      assert msg =~ "nope/1"

      bad_arity =
        Decl.parse(~S|@external(:ex, "./codec.ffi.ex", "enc") pub def f(a Int53, b Int53) Int53|)

      assert {:error, msg2} = External.resolve(bad_arity, dir)
      assert msg2 =~ "enc/2"
    end

    test "render refuses a file-reference until bundling lands (ADR-0080 §7 b)" do
      assert_raise ArgumentError, ~r/bundling is the next build-system phase/, fn ->
        External.render({:file, "./codec.ffi.mjs", "encode"}, [])
      end
    end
  end

  defp node_run(js, expr) do
    case System.find_executable("node") do
      nil ->
        :no_node

      node ->
        path = Path.join(System.tmp_dir!(), "rian_ext_#{System.unique_integer([:positive])}.mjs")
        File.write!(path, js <> "\nconsole.log(String(#{expr}));\n")
        {out, 0} = System.cmd(node, [path])
        File.rm(path)
        String.trim(out)
    end
  end
end

defmodule Rian.Pkg.RebarTest do
  @moduledoc "BEAM backend (ADR-0082 step 2): rian.toml manifest -> rebar.config + OTP .app.src."
  use ExUnit.Case, async: true

  alias Rian.Manifest
  alias Rian.Pkg.Rebar

  # parse a generated artifact as Erlang terms — proves it is well-formed.
  defp consult(content) do
    path = Path.join(System.tmp_dir!(), "rian_rebar_#{System.unique_integer([:positive])}.config")
    File.write!(path, content)
    on_exit(fn -> File.rm(path) end)
    :file.consult(String.to_charlist(path))
  end

  test "rebar.config is deterministic and consults as valid Erlang terms" do
    m = %Manifest{name: "my_app", version: "0.1.0"}
    rc = Rebar.rebar_config(m)
    assert {:ok, terms} = consult(rc)
    assert {:deps, []} in terms
    assert Rebar.rebar_config(m) == rc
  end

  test "a non-empty [deps] is a loud error — no resolver yet (invariant 4)" do
    m = %Manifest{name: "x", version: "0.0.0", deps: %{"cowboy" => "2.0"}}
    assert_raise ArgumentError, ~r/no resolver/, fn -> Rebar.rebar_config(m) end
  end

  test "app.src is a valid OTP application resource listing the modules" do
    m = %Manifest{name: "my_app", version: "0.3.0"}
    src = Rebar.app_src(m, [:"Elixir.Foo", :"Elixir.Bar"])

    assert {:ok, [{:application, :my_app, kw}]} = consult(src)
    assert Keyword.fetch!(kw, :vsn) == ~c"0.3.0"
    assert Keyword.fetch!(kw, :modules) == [:"Elixir.Foo", :"Elixir.Bar"]
    assert Keyword.fetch!(kw, :applications) == [:kernel, :stdlib]
  end

  test "the OTP app name turns a hyphen into an underscore (a valid atom)" do
    assert Rebar.app_name(%Manifest{name: "my-app", version: "0.0.0"}) == "my_app"
  end
end

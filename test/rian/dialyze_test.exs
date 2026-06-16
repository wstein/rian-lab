defmodule Mix.Tasks.Rian.DialyzeTest do
  use ExUnit.Case, async: false

  @moduledoc """
  `mix rian.dialyze` — the external Dialyzer oracle (ADR-0026). The full analysis
  needs the `dialyzer` OTP app + a PLT, so it is `@tag :dialyzer` (out of the default
  loop). The availability guard is verified everywhere.
  """

  alias Mix.Tasks.Rian.Dialyze

  @clean "mod Dz do\n  pub def add(a Int53, b Int53) Int53 := a + b\nend\n"

  defp write(src) do
    path = Path.join(System.tmp_dir!(), "rian_dz_#{:erlang.unique_integer([:positive])}.rian")
    File.write!(path, src)
    path
  end

  describe "availability guard (runs everywhere)" do
    test "dialyzer_available?/0 reflects the OTP install" do
      assert is_boolean(Dialyze.dialyzer_available?())
    end

    test "no such file raises a clear usage error" do
      assert_raise Mix.Error, ~r/no such file/, fn -> Dialyze.run(["/no/such/file.rian"]) end
    end

    test "when Dialyzer is absent, fails cleanly — never an UndefinedFunctionError" do
      path = write(@clean)

      if Dialyze.dialyzer_available?() do
        # present: the guard passes; the full path is covered by the :dialyzer test
        assert true
      else
        assert_raise Mix.Error, ~r/Dialyzer is not available/, fn -> Dialyze.run([path]) end
      end
    end
  end

  describe "the oracle (needs Dialyzer + PLT)" do
    @tag :dialyzer
    test "a clean Rian module is warning-free (Dialyzer agrees with Rian's checker)" do
      Mix.shell(Mix.Shell.Process)
      path = write(@clean)

      try do
        Dialyze.run([path])
      catch
        :exit, _ -> :ok
      end

      # a clean module must not produce a Dialyzer warning line
      refute Enum.any?(drain_shell(), &(&1 =~ "warning(s)"))
    after
      Mix.shell(Mix.Shell.IO)
    end
  end

  defp drain_shell(acc \\ []) do
    receive do
      {:mix_shell, _, [msg]} -> drain_shell([msg | acc])
    after
      0 -> acc
    end
  end
end

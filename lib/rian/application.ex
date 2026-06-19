defmodule Rian.Application do
  @moduledoc false
  use Application
  use Rian.Ann

  @rian_sig "pub def start(type _Unk, args _Unk) _Unk"
  @impl true
  def start(_type, _args) do
    maybe_register_smart_cell()
    Supervisor.start_link([], strategy: :one_for_one, name: Rian.Supervisor)
  end

  # Register the Livebook smart cell only when Kino is present — i.e. inside a
  # Livebook runtime, or this project's own dev/test (where Kino is an optional
  # dep). The compiler core itself has no runtime dependency on Kino, so a plain
  # consumer of the library that never loads Kino is unaffected.
  @spec maybe_register_smart_cell() :: term()
  defp maybe_register_smart_cell do
    if Code.ensure_loaded?(Kino.SmartCell) and Code.ensure_loaded?(Rian.Livebook.SmartCell) do
      Kino.SmartCell.register(Rian.Livebook.SmartCell)
    end
  end
end

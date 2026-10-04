defmodule Jido.Examples.Research.DataDefinedTopology.RecordCount do
  @moduledoc "Owns the number of committed Records for selected Agent definitions."
  use Jido.Plugin

  @impl true
  def state_spec(_opts), do: {:records, Zoi.integer() |> Zoi.default(0)}

  @impl true
  def reduce(reduction, _opts), do: {:ok, reduction.plugin_state + 1}
end

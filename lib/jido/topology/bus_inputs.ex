defmodule Jido.Topology.BusInputs do
  @moduledoc false
  use Jido.Plugin

  @impl true
  defdelegate child_spec(init), to: Jido.Topology.BusInputs.Server

  @impl true
  defdelegate await_ready(runtime, opts), to: Jido.Topology.BusInputs.Server
end

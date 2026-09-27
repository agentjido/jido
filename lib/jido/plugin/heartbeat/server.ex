defmodule Jido.Plugin.Heartbeat.Server do
  @moduledoc "Separate Server facet for packages that reuse the Heartbeat runtime."
  use Jido.AgentServer.Plugin

  defdelegate validate_options(opts), to: Jido.Plugin.Heartbeat
  defdelegate child_spec(init), to: Jido.Plugin.Heartbeat
end

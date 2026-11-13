defmodule Jido.Examples.AgentShutdown do
  @moduledoc "Applies explicit shutdown at activation or instance scope."

  alias Jido.Agent.Address

  def stop_activation(instance, %Address{} = address) do
    with {:ok, server} <- Jido.resolve_agent(instance, address),
         {:ok, snapshot} <- Jido.AgentServer.stop(server),
         do: {:ok, snapshot}
  end

  def reactivate(instance, %Address{} = address), do: Jido.activate_agent(instance, address)
end

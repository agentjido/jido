defmodule Jido.Examples.AgentShutdown do
  @moduledoc "Applies explicit shutdown at activation or instance scope."

  alias Jido.Agent.Ref

  def stop_activation(instance, %Ref{} = ref) do
    with {:ok, server} <- Jido.resolve_agent(instance, ref),
         {:ok, snapshot} <- Jido.AgentServer.stop(server),
         do: {:ok, snapshot}
  end

  def reactivate(instance, %Ref{} = ref), do: Jido.activate_agent(instance, ref)
end

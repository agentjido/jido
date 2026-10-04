defmodule Jido.Examples.TurnUpgrade do
  @moduledoc """
  Coordinates one release installation at the Agent Server idle boundary.

  The installation callback belongs to the deployment system. It must return
  `:ok` or `{:error, reason}` and must not call the same Agent Server.
  """
  use Jido.Agent, name: "runtime_turn_upgrade"

  agent do
    schema Zoi.object(%{deployments: Zoi.list(Zoi.string()) |> Zoi.default([])})
  end

  routes do
    signal_source "/examples/runtime/turn_upgrade"

    route "examples.runtime.turn_upgrade.record", as: :record do
      action %{release: release},
        schema: Zoi.object(%{release: Zoi.string() |> Zoi.min(1)}),
        context: context do
        {:ok,
         %{
           context.agent_state
           | deployments: context.agent_state.deployments ++ [release]
         }}
      end
    end
  end

  @doc "Runs an external release installation after the Server becomes idle."
  @spec install_release(Jido.AgentServer.server(), (-> :ok | {:error, term()}), timeout()) ::
          :ok | {:error, term()}
  def install_release(server, install, timeout \\ 5_000) when is_function(install, 0) do
    Jido.AgentServer.upgrade(server, install, timeout)
  end
end

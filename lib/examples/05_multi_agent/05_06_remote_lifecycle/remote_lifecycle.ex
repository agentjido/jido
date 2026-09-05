defmodule Jido.Examples.RemoteLifecycle.RequestWorker do
  @moduledoc false
  use Jido.Action,
    name: "example_remote_lifecycle_worker",
    schema:
      Zoi.object(%{
        target_node: Zoi.atom(),
        worker_module: Zoi.module() |> Zoi.default(Jido.Examples.RemoteCounter)
      })

  def run(input, %{agent_state: state}) do
    directive =
      Jido.Agent.Directive.spawn_agent(input.worker_module, :worker,
        node: input.target_node,
        restart: :temporary
      )

    {:ok, state, [directive]}
  end
end

defmodule Jido.Examples.RemoteLifecycle do
  @moduledoc """
  DIST-02: distinguish an observed child exit from loss of its node connection.

  `:noconnection` means unreachable. It does not establish that the child or
  its node stopped. The default child policy stops work when it loses its
  parent connection. Reconnect does not automatically create a replacement.
  """
  use Jido.Agent, name: "example_remote_lifecycle"

  agent do
    schema Zoi.object(%{observations: Zoi.list(Zoi.map()) |> Zoi.default([])})
  end

  routes do
    signal_source "/examples/remote/lifecycle"

    route "examples.remote.create_worker", __MODULE__.RequestWorker do
      define :create_worker, args: [:target_node]
    end

    route "jido.agent.child.exit" do
      action input, name: "example_remote_lifecycle_exit", context: context do
        observation = if input.reason == :noconnection, do: :unreachable, else: :exited
        event = %{child_id: input.child_id, observation: observation, reason: input.reason}
        {:ok, %{context.agent_state | observations: context.agent_state.observations ++ [event]}}
      end
    end

    route "jido.agent.child.started", Jido.Examples.KeepState
  end
end

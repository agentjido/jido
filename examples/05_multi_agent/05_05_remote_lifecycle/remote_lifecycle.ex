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
    signal_source "/examples/multi_agent/remote_lifecycle"

    route "examples.multi_agent.remote_lifecycle.create_worker" do
      action %{target_node: target_node},
        schema: Zoi.object(%{target_node: Zoi.atom()}),
        context: context do
        directive =
          Jido.Agent.Directive.spawn_child(Jido.Examples.RemoteCounter, :worker,
            node: target_node,
            restart: :temporary
          )

        {:ok, context.agent_state, [directive]}
      end

      define :create_worker, args: [:target_node]
    end

    route "jido.agent.child.exit" do
      action input, context: context do
        observation = if input.reason == :noconnection, do: :unreachable, else: :exited
        event = %{child_id: input.child_id, observation: observation, reason: input.reason}
        {:ok, %{context.agent_state | observations: context.agent_state.observations ++ [event]}}
      end
    end

    route "jido.agent.child.started", Jido.Examples.Support.KeepState
  end
end

defmodule Jido.AgentServer.Signal.ChildStarted do
  @moduledoc false

  use Jido.Signal,
    type: "jido.agent.child.started",
    default_source: "/agent",
    schema:
      Zoi.object(%{
        parent_id: Zoi.string(description: "Parent Agent id"),
        child_id: Zoi.string(description: "Child Agent id"),
        child_partition: Zoi.any(description: "Child partition") |> Zoi.optional(),
        child_module: Zoi.any(description: "Child Agent module"),
        tag: Zoi.any(description: "Tracked child tag"),
        pid: Zoi.any(description: "Child Agent Server PID"),
        meta: Zoi.map(description: "Relationship metadata") |> Zoi.default(%{})
      })

  def for_child(parent_id, child, restarted? \\ false) do
    signal =
      new!(
        %{
          parent_id: parent_id,
          child_id: child.id,
          child_partition: child.partition,
          child_module: child.module,
          tag: child.tag,
          pid: child.pid,
          meta: Map.put(child.meta, :restarted, restarted?)
        },
        source: "/agent/#{parent_id}"
      )
      |> Jido.AgentServer.CreationCause.put(child.creation_cause)

    {:ok, signal} = Jido.Signal.put_context(signal, "jidochildactivation", child.activation_id)
    signal
  end
end

defmodule Jido.Persistence.AgentCheckpoint do
  @moduledoc false
  alias Jido.Agent
  alias Jido.Persistence.Snapshot

  # The storage envelope already holds revision and identity. Snapshot stores
  # the complete accepted Agent once; source modules do not rebuild its fields.
  def checkpoint(agent, context \\ %{}), do: checkpoint(agent, context, &keep_state/2)

  def checkpoint(%Agent{} = agent, context, convert_state) when is_map(context),
    do: Snapshot.dump(agent, context, convert_state)

  def checkpoint(_, _, _),
    do: Agent.Error.fail(:invalid_snapshot, [], "Expected an Agent instance and context Map")

  def restore(module, snapshot, context \\ %{}),
    do: restore(module, snapshot, context, &keep_state/2)

  def restore(module, snapshot, context, convert_state) do
    with {:ok, agent} <- Snapshot.load(snapshot, context, convert_state) do
      if agent.module == module,
        do: {:ok, agent},
        else:
          Agent.Error.fail(
            :snapshot_identity,
            [:agent, :module],
            "Saved Agent origin differs from the requested origin"
          )
    end
  end

  def default_checkpoint(agent, context),
    do: Snapshot.dump(agent, context, &keep_state/2, :default)

  def default_restore(module, snapshot, context), do: restore(module, snapshot, context)
  defp keep_state(_agent, state), do: {:ok, state}
end

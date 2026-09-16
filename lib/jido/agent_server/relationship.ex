defmodule Jido.AgentServer.Relationship do
  @moduledoc false

  alias Jido.AgentServer.{ChildInfo, ParentRef, State}
  alias Jido.RuntimeStore

  @hive :agent_relationships

  @spec record(String.t(), term(), term(), term(), map()) :: map()
  def record(parent_id, parent_partition, tag, creation_cause, meta) do
    %{
      parent_id: parent_id,
      parent_partition: parent_partition,
      tag: tag,
      creation_cause: creation_cause,
      meta: meta
    }
  end

  def put_own(%State{jido: jido, parent: %ParentRef{} = parent} = data)
      when is_atom(jido) and not is_nil(jido) do
    RuntimeStore.put(
      jido,
      @hive,
      Jido.partition_key(data.agent.id, data.partition),
      record(parent.id, parent.partition, parent.tag, parent.creation_cause, parent.meta)
    )
  end

  def put_own(_data), do: :ok

  def put_child(%State{} = data, %ChildInfo{} = child) do
    put_child(
      data,
      child.id,
      child.partition,
      child.tag,
      child.meta,
      child.creation_cause
    )
  end

  def put_child(%State{jido: jido} = data, child_id, child_partition, tag, meta, cause)
      when is_atom(jido) and not is_nil(jido) do
    RuntimeStore.put(
      jido,
      @hive,
      Jido.partition_key(child_id, child_partition),
      record(data.agent.id, data.partition, tag, cause, meta)
    )
  end

  def put_child(_data, _child_id, _partition, _tag, _meta, _cause), do: :ok

  def delete_own(%State{jido: jido} = data)
      when is_atom(jido) and not is_nil(jido) do
    RuntimeStore.delete(jido, @hive, Jido.partition_key(data.agent.id, data.partition))
  end

  def delete_own(_data), do: :ok

  def delete_child(%State{jido: jido}, child)
      when is_atom(jido) and not is_nil(jido) do
    RuntimeStore.delete(jido, @hive, Jido.partition_key(child.id, child.partition))
  end

  def delete_child(_data, _child), do: :ok
end

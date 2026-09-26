defmodule Jido.Topology.EntryMetadata do
  @moduledoc false

  @agent_fields [:key, :module, :initial_state, :depends_on, :node]
  @entries [
    agent: {:agents, @agent_fields},
    group: {:groups, @agent_fields ++ [:count, :members, :key_by]},
    resource: {:resources, [:key, :kind, :config]},
    owns: {:relationships, [:parent, :child, :on_parent_exit]},
    subscribe: {:connections, [:agent, :to, :path]},
    include: {:includes, [:key, :topology, :inputs, :bindings]},
    import: {:imports, [:key, :kind]},
    export: {:exports, [:key, :kind, :from]},
    startup: {nil, [:concurrency, :max_agents, :retry_interval, :task_timeout]},
    binding: {nil, [:key, :to]}
  ]

  def fields(kind) when is_atom(kind), do: @entries |> Keyword.fetch!(kind) |> elem(1)
  def collection(kind) when is_atom(kind), do: @entries |> Keyword.fetch!(kind) |> elem(0)

  def collections do
    for {kind, {collection, _fields}} <- @entries, not is_nil(collection), do: {kind, collection}
  end
end

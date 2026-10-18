defmodule Jido.Agent.Diff do
  @moduledoc "Final data differences. Runtime code decides which process changes are required."
  @empty %{added: [], removed: [], updated: [], order: %{before: [], after: []}}
  defstruct fields: %{},
            agents: @empty,
            routes: @empty,
            connections: @empty,
            extensions: @empty,
            state: nil

  @type t :: %__MODULE__{}

  @doc "Compares canonical Agent values; order and cancelled edits remain unambiguous."
  def between(before, after_agent) do
    %__MODULE__{
      fields:
        for(
          {field, value} <- Map.from_struct(after_agent),
          field not in [:state, :routes, :topology, :extensions],
          Map.fetch!(before, field) !== value,
          into: %{},
          do: {field, %{before: Map.fetch!(before, field), after: value}}
        ),
      agents: collection(before.topology.agents, after_agent.topology.agents, & &1.name),
      routes: collection(before.routes, after_agent.routes, & &1.path),
      connections:
        collection(
          before.topology.connections,
          after_agent.topology.connections,
          &{&1.from, &1.to, &1.path}
        ),
      extensions: collection(before.extensions, after_agent.extensions, & &1.provider),
      state:
        if(before.state === after_agent.state,
          do: nil,
          else: %{before: before.state, after: after_agent.state}
        )
    }
  end

  @doc "True when neither data nor declaration order changed."
  def empty?(%__MODULE__{} = diff) do
    not Enum.any?(
      [:fields, :state, :agents, :routes, :connections, :extensions],
      &changed?(diff, &1)
    )
  end

  @doc "True when one collection or the state changed."
  def changed?(%__MODULE__{fields: fields}, :fields), do: fields != %{}
  def changed?(%__MODULE__{state: state}, :state), do: state != nil

  def changed?(%__MODULE__{} = diff, field)
      when field in [:agents, :routes, :connections, :extensions] do
    c = Map.fetch!(diff, field)
    c.added != [] or c.removed != [] or c.updated != [] or c.order.before != c.order.after
  end

  defp collection(before, after_values, key) do
    old = Map.new(before, &{key.(&1), &1})
    new = Map.new(after_values, &{key.(&1), &1})

    %{
      added: Enum.reject(after_values, &Map.has_key?(old, key.(&1))),
      removed: Enum.reject(before, &Map.has_key?(new, key.(&1))),
      updated:
        for(
          value <- after_values,
          id = key.(value),
          Map.has_key?(old, id),
          old[id] !== value,
          do: %{before: old[id], after: value}
        ),
      order: %{before: Enum.map(before, key), after: Enum.map(after_values, key)}
    }
  end
end

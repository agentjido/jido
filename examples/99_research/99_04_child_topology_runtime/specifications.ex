defmodule Jido.Examples.Research.ChildTopologyRuntime.Specifications do
  @moduledoc "Proposed child runtime data declarations. The current core rejects children."

  alias Jido.Agent
  alias Jido.Topology
  alias Jido.Examples.Research.ChildTopologyRuntime.{Child, Parent, Worker}

  @command "examples.research.child_runtime.record"
  @export "examples.research.child_runtime.completed"

  def command, do: @command
  def exported_event, do: @export
  def private_event, do: "examples.research.child_runtime.private.progress"

  def child_entry(form, opts \\ []) do
    with {:ok, child} <- child(form) do
      {:ok,
       Map.merge(child, %{
         key: Keyword.get(opts, :key, :team),
         activation: :lazy,
         gate: %{
           commands: [%{type: @command, member: :alice}],
           events: Keyword.get(opts, :events, [@export])
         },
         max_restarts: Keyword.get(opts, :max_restarts, 1),
         max_seconds: 5
       })}
    end
  end

  def parent(parent_form, child_form, opts \\ []) do
    with {:ok, child} <- child_entry(child_form, opts) do
      Topology.new(Map.put(parent_attrs(parent_form), :children, [child]))
    end
  end

  def parent_attrs(:dsl), do: Map.from_struct(Parent.topology())

  def parent_attrs(:data),
    do: %{name: "child_runtime_parent", resources: [%{key: :signals, kind: :bus}]}

  def child(:dsl), do: {:ok, %{topology: Child}}
  def child(:data), do: {:ok, %{topology: Child.topology(), director: Child.owner()}}

  def child(:data_agents) do
    with {:ok, definition} <- Topology.new(%{Child.topology() | agents: data_entries()}),
         do: {:ok, %{topology: definition, director: Child.owner()}}
  end

  def data_entries do
    for entry <- Child.topology().agents do
      definition =
        Agent.new!(
          module: Worker,
          name: to_string(entry.key),
          schema: Worker.definition().schema,
          routes: Worker.definition().routes,
          metadata: %{"document_id" => "child/#{entry.key}"}
        )

      %{entry | module: definition}
    end
  end

  def nested(levels) when levels > 0 do
    Enum.reduce(1..levels, %{name: "leaf"}, fn level, child ->
      %{
        name: "level-#{level}",
        children: [
          %{key: :next, topology: child, activation: :lazy, gate: %{commands: [], events: []}}
        ]
      }
    end)
  end

  def nested_parent do
    with {:ok, leaf} <- child_entry(:dsl),
         {:ok, middle} <-
           Topology.new(name: "middle", children: [leaf]),
         {:ok, entry} <- child_entry(:data) do
      entry = %{
        entry
        | topology: middle,
          gate: %{commands: [%{type: @command, member: {:child, :team}}], events: []}
      }

      Topology.new(Map.put(parent_attrs(:data), :children, [entry]))
    end
  end
end

defmodule Jido.Examples.Research.ChildTopologyRuntime.CycleA do
  @moduledoc false
  def topology do
    %{
      name: "cycle-a",
      children: [
        %{
          key: :b,
          topology: Jido.Examples.Research.ChildTopologyRuntime.CycleB,
          gate: %{commands: [], events: []}
        }
      ]
    }
  end
end

defmodule Jido.Examples.Research.ChildTopologyRuntime.CycleB do
  @moduledoc false
  def topology do
    %{
      name: "cycle-b",
      children: [
        %{
          key: :a,
          topology: Jido.Examples.Research.ChildTopologyRuntime.CycleA,
          gate: %{commands: [], events: []}
        }
      ]
    }
  end
end

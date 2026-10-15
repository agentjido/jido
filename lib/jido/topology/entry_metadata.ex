defmodule Jido.Topology.EntryMetadata do
  @moduledoc false

  @agent_fields [
    key: [type: :any, required: true],
    module: [type: :atom],
    definition: [type: :any],
    initial_state: [type: :any, default: %{}],
    depends_on: [type: {:list, :any}, default: []],
    node: [type: :any]
  ]
  @entries [
    agent: {:agents, @agent_fields},
    group:
      {:groups,
       @agent_fields ++
         [count: [type: :any, default: 1], members: [type: :any], key_by: [type: :any]]},
    resource:
      {:resources,
       [
         key: [type: :any, required: true],
         kind: [type: :atom, default: :bus],
         config: [type: :any, default: []]
       ]},
    owns:
      {:relationships,
       [
         parent: [type: :any, required: true],
         child: [type: :any, required: true],
         on_parent_exit: [type: {:in, [:stop, :continue, :emit_orphan]}, default: :stop]
       ]},
    subscribe:
      {:connections,
       [
         agent: [type: :any, required: true],
         to: [type: :any, required: true],
         path: [type: :string, required: true]
       ]},
    include:
      {:includes,
       [
         key: [type: :any, required: true],
         topology: [type: :any, required: true],
         inputs: [type: :map, default: %{}],
         bindings: [type: :any, default: []]
       ]},
    runtime_child:
      {:children,
       [
         key: [type: :any],
         topology: [type: :any],
         director: [type: :any],
         input: [type: :any, default: %{}],
         activation: [type: :any, default: :lazy],
         gate: [type: :any, default: %{}],
         max_restarts: [type: :any, default: 3],
         max_seconds: [type: :any, default: 5]
       ]},
    import: {:imports, [key: [type: :any, required: true], kind: [type: :atom]]},
    export:
      {:exports,
       [
         key: [type: :any, required: true],
         kind: [type: :atom],
         from: [type: :any, required: true]
       ]},
    startup:
      {nil,
       [
         concurrency: [type: :pos_integer, default: 32],
         max_agents: [type: :pos_integer, default: 10_000],
         retry_interval: [type: :pos_integer, default: 1_000],
         task_timeout: [type: :pos_integer, default: 10_000]
       ]},
    binding: {nil, [key: [type: :any, required: true], to: [type: :any, required: true]]}
  ]

  def schema(kind), do: @entries |> Keyword.fetch!(kind) |> elem(1)
  def fields(kind), do: Keyword.keys(schema(kind))

  def defaults(kind),
    do:
      Map.new(
        for {key, opts} <- schema(kind),
            Keyword.has_key?(opts, :default),
            do: {key, opts[:default]}
      )

  def default(kind, field), do: Map.fetch!(defaults(kind), field)

  def apply_defaults(kind, attrs) do
    # Count defaults only apply to groups without explicit member data.
    defaults = if kind == :group, do: Map.delete(defaults(kind), :count), else: defaults(kind)
    Map.merge(defaults, attrs)
  end

  def collections do
    for {kind, {collection, _schema}} <- @entries, not is_nil(collection), do: {kind, collection}
  end
end

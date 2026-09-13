defmodule JidoTest.Authoring.Topology.Fixtures.Worker do
  use Jido.Agent,
    name: "authoring_worker",
    schema:
      Zoi.object(%{
        label: Zoi.string() |> Zoi.default("worker"),
        value: Zoi.integer() |> Zoi.default(0)
      })
end

defmodule JidoTest.Authoring.Topology.Fixtures.SetValue do
  use Jido.Action, name: "authoring_set_value", schema: Zoi.object(%{value: Zoi.integer()})
  def run(%{value: value}, %{agent_state: state}), do: {:ok, %{state | value: value}}
end

defmodule JidoTest.Authoring.Topology.Fixtures.Inbox do
  use Jido.Topology.Plugin

  def contribute(context, _opts) do
    key = "inbox_" <> context.agent_key

    {:ok,
     %Jido.Topology.Plugin.Contribution{
       plugin: context.plugin,
       resources: [%{key: key}],
       connections: [%{agent: context.agent_key, to: key, path: "authoring.work"}]
     }}
  end
end

defmodule JidoTest.Authoring.Topology.Fixtures.InboxPackage do
  use Jido.Plugin, topology: JidoTest.Authoring.Topology.Fixtures.Inbox
end

defmodule JidoTest.Authoring.Topology.Fixtures.PluginWorker do
  use Jido.Agent,
    name: "authoring_plugin_worker",
    schema: Zoi.object(%{value: Zoi.integer() |> Zoi.default(0)}),
    plugins: [JidoTest.Authoring.Topology.Fixtures.InboxPackage]
end

defmodule JidoTest.Authoring.Topology.Fixtures.Role do
  defstruct [:key, :module, :__spark_metadata__]
end

defmodule JidoTest.Authoring.Topology.Fixtures.Roles do
  @role %Spark.Dsl.Entity{
    name: :role,
    target: JidoTest.Authoring.Topology.Fixtures.Role,
    args: [:key, :module],
    schema: [key: [type: :atom, required: true], module: [type: :atom, required: true]]
  }
  use Spark.Dsl.Extension,
    dsl_patches: [%Spark.Dsl.Patch.AddEntity{section_path: [:topology, :agents], entity: @role}]

  @behaviour Jido.Topology.Extension
  def lower_topology(config, entities) do
    {roles, rest} =
      Enum.split_with(entities, &is_struct(&1, JidoTest.Authoring.Topology.Fixtures.Role))

    agents = config.agents ++ Enum.map(roles, &%{key: &1.key, module: &1.module})

    {:ok,
     %{config | agents: agents, metadata: Map.put(config.metadata, :role_count, length(roles))},
     rest}
  end
end

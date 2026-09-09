defmodule Jido.Topology.PluginIntegrationTest do
  use ExUnit.Case, async: true

  alias Jido.Topology
  alias Jido.Topology.Plan
  alias Jido.Topology.Plugin, as: TopologyPlugin
  alias Jido.Topology.Plugin.Contribution

  defmodule BusFacet do
    @moduledoc false
    use Jido.Topology.Plugin

    def contribute(context, opts) do
      key = Keyword.get(opts, :fixed_bus, Keyword.fetch!(opts, :prefix) <> context.agent_key)

      {:ok,
       %Contribution{
         plugin: context.plugin,
         resources: [%{key: key, config: []}],
         connections: [%{agent: context.agent_key, to: key, path: "plugin.work"}]
       }}
    end
  end

  defmodule BusPackage do
    @moduledoc false
    use Jido.Plugin,
      topology: BusFacet,
      option_keys: [topology: [:prefix, :fixed_bus]]
  end

  defmodule AuditPackage do
    @moduledoc false
    use Jido.Plugin,
      topology: BusFacet,
      option_keys: [topology: [:prefix]]
  end

  defmodule Worker do
    @moduledoc false
    use Jido.Agent,
      name: "topology_plugin_worker",
      plugins: [{BusPackage, prefix: "inbox_"}, {AuditPackage, prefix: "audit_"}]
  end

  defmodule ConflictingWorker do
    @moduledoc false
    use Jido.Agent,
      name: "conflicting_topology_plugin_worker",
      plugins: [{BusPackage, prefix: "unused_", fixed_bus: "events"}]
  end

  defmodule OwnershipFacet do
    @moduledoc false
    use Jido.Topology.Plugin

    def contribute(context, opts) do
      {:ok,
       %Contribution{
         plugin: context.plugin,
         relationships: [
           %{
             parent: context.agent_key,
             child: Keyword.fetch!(opts, :child),
             on_parent_exit: :stop
           }
         ]
       }}
    end
  end

  defmodule OwnershipPackage do
    @moduledoc false
    use Jido.Plugin,
      topology: OwnershipFacet,
      option_keys: [topology: [:child]]
  end

  defmodule Parent do
    @moduledoc false
    use Jido.Agent,
      name: "topology_plugin_parent",
      plugins: [{OwnershipPackage, child: "child"}]
  end

  test "instantiation adds ordered Agent and group contributions without changing the definition" do
    definition =
      Topology.new!(
        name: "plugin_contributions",
        resources: [%{key: "explicit", config: []}],
        agents: [%{key: "alpha", module: Worker}],
        groups: [%{key: "workers", module: Worker, count: 2}]
      )

    assert Enum.map(definition.resources, & &1.key) == ["explicit"]
    assert {:ok, expanded} = TopologyPlugin.expand_definition(definition)

    assert Enum.map(expanded.resources, & &1.key) == [
             "explicit",
             "inbox_alpha",
             "audit_alpha",
             "inbox_workers",
             "audit_workers"
           ]

    assert {:ok, instance} = Topology.instantiate(definition, id: "plugin-plan")
    assert instance.definition == definition
    assert Map.has_key?(instance.plan.resources, "bus/inbox_alpha")
    assert Map.has_key?(instance.plan.resources, "bus/audit_alpha")
    assert Map.has_key?(instance.plan.resources, "bus/inbox_workers")

    assert instance.plan.agents["agent/alpha"].subscriptions == [
             %{bus: "bus/inbox_alpha", path: "plugin.work"},
             %{bus: "bus/audit_alpha", path: "plugin.work"}
           ]

    for member <- 1..2 do
      assert instance.plan.agents["group/workers/#{member}"].subscriptions == [
               %{bus: "bus/inbox_workers", path: "plugin.work"},
               %{bus: "bus/audit_workers", path: "plugin.work"}
             ]
    end

    assert {:ok, direct_plan} = Plan.build(definition, instance.id, instance.input)
    assert direct_plan == instance.plan
  end

  test "included definitions receive scoped contributions" do
    child =
      Topology.new!(
        name: "plugin_child",
        agents: [%{key: "worker", module: Worker}]
      )

    root =
      Topology.new!(
        name: "plugin_root",
        includes: [%{key: "child", topology: child}]
      )

    assert {:ok, instance} = Topology.instantiate(root, id: "plugin-components")
    assert Map.has_key?(instance.plan.resources, "component/child/bus/inbox_worker")
    assert Map.has_key?(instance.plan.resources, "component/child/bus/audit_worker")

    assert instance.plan.agents["component/child/agent/worker"].subscriptions == [
             %{bus: "component/child/bus/inbox_worker", path: "plugin.work"},
             %{bus: "component/child/bus/audit_worker", path: "plugin.work"}
           ]
  end

  test "a contributed ownership relationship enters the common dependency graph" do
    definition =
      Topology.new!(
        name: "plugin_ownership",
        agents: [
          %{key: "parent", module: Parent},
          %{key: "child", module: Worker}
        ]
      )

    assert {:ok, instance} = Topology.instantiate(definition, id: "plugin-ownership")
    assert instance.plan.agents["agent/child"].parent == "agent/parent"
    assert "agent/parent" in instance.plan.agents["agent/child"].depends_on
  end

  test "common topology validation rejects a conflicting contribution before activation" do
    definition =
      Topology.new!(
        name: "plugin_conflict",
        resources: [%{key: "events", config: []}],
        agents: [%{key: "worker", module: ConflictingWorker}]
      )

    assert {:error, error} = Topology.instantiate(definition, id: "plugin-conflict")
    assert Exception.message(error) =~ "Duplicate topology key"
  end
end

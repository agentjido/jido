defmodule Jido.Topology.CompositionTest do
  use ExUnit.Case, async: true
  alias Jido.Examples.Topology.{Cell, ComposedFormats, ComposedSystem, WorkerTeam}
  alias Jido.Topology
  alias Jido.Topology.{Builder, Codec, Plan, Ref, Reference}

  defmodule RecursiveSource do
    def __topology_config__ do
      %{name: "recursive", includes: [%{key: "again", topology: __MODULE__}]}
    end
  end

  test "DSL, Builder, and stored JSON retain the same composition and plan" do
    definition = ComposedSystem.topology()
    assert {:ok, ^definition} = Builder.build(ComposedFormats.builder())
    assert {:ok, json} = ComposedFormats.json()
    document = JSON.decode!(json)
    assert document["version"] == 2
    assert length(document["includes"]) == 2

    assert document["includes"] |> hd() |> Map.fetch!("topology") |> Map.fetch!("type") ==
             "jido.topology"

    assert {:ok, ^definition} = Codec.decode(document, ComposedFormats.registry())
    assert {:ok, ^definition} = ComposedFormats.from_file()
    assert {:ok, instance} = ComposedSystem.new(id: "composed")
    assert {:ok, ^instance} = Codec.decode(document, ComposedFormats.registry(), id: "composed")
    assert {:ok, ^instance} = Builder.build(ComposedFormats.builder(), id: "composed")
    assert map_size(instance.plan.agents) == 8
    assert map_size(instance.plan.resources) == 1
    assert instance.definition.startup.concurrency == 4
  end

  test "inputs and identities are isolated while Bus bindings share one owner" do
    instance = ComposedSystem.new!(id: "system", input: %{east_workers: 1, west_workers: 2})
    east = instance.plan.agents["component/east/group/workers/1"]
    west = instance.plan.agents["component/west/group/workers/1"]
    assert east.id != west.id
    assert east.initial_state.label == "east"
    assert west.initial_state.label == "west"
    assert east.subscriptions == west.subscriptions
    assert east.subscriptions == [%{bus: "bus/events", path: "topology.work"}]
    assert east.parent == "component/east/agent/coordinator"
    assert instance.plan.agents[east.parent].parent == "agent/director"
    assert instance.plan.components[["east"]].agents == 2
    assert instance.plan.components[["east"]].resources == 0
  end

  test "nested topologies can re-export public endpoints" do
    region =
      Builder.new(name: "region")
      |> Builder.schema(Zoi.object(%{count: Zoi.integer() |> Zoi.default(2)}))
      |> Builder.import_bus(:events)
      |> Builder.include(:team, WorkerTeam,
        inputs: %{worker_count: Reference.input(:count)},
        bindings: %{events: :events}
      )
      |> Builder.export(:agent, :leader, from: Ref.ref(:team, :leader))
      |> Builder.export(:group, :workers, from: Ref.ref(:team, :workers))
      |> Builder.build!()

    root =
      Builder.new(name: "root")
      |> Builder.bus(:bus)
      |> Builder.include(:region, region, inputs: %{count: 3}, bindings: %{events: :bus})
      |> Builder.build!()

    {:ok, document, registry} = Codec.encode(root)
    assert {:ok, ^root} = Codec.decode(JSON.decode!(JSON.encode!(document)), registry)
    {:ok, instance} = Topology.instantiate(root, id: "root")

    assert Plan.resolve(instance.plan, Ref.ref(:region, :leader), :agent) ==
             "component/region/component/team/agent/coordinator"

    assert Plan.resolve(instance.plan, Ref.ref(:region, :workers), :agent, 3) ==
             "component/region/component/team/group/workers/3"

    assert map_size(instance.plan.agents) == 4
  end

  test "private names and wrong endpoint kinds are rejected" do
    base = ComposedFormats.builder()

    assert {:error, _} =
             base |> Builder.owns(:director, Ref.ref(:east, :coordinator)) |> Builder.build()

    assert {:error, _} =
             base |> Builder.owns(Ref.ref(:east, :workers), :director) |> Builder.build()

    assert {:error, _} =
             base
             |> Builder.subscribe(:director, to: Ref.ref(:east, :leader), path: "**")
             |> Builder.build()

    plan = ComposedSystem.new!(id: "private").plan
    assert Plan.resolve(plan, Ref.ref(:east, :coordinator), :agent) == nil

    assert Plan.resolve(plan, Ref.ref(:east, :leader), :agent) ==
             "component/east/agent/coordinator"
  end

  test "imports require exact bindings and correct resource kinds" do
    base = Builder.new(name: "imports") |> Builder.bus(:bus) |> Builder.agent(:cell, Cell)
    assert {:error, _} = base |> Builder.include(:team, WorkerTeam) |> Builder.build()

    assert {:error, _} =
             base
             |> Builder.include(:team, WorkerTeam, bindings: %{events: :bus, extra: :bus})
             |> Builder.build()

    assert {:error, _} =
             base
             |> Builder.include(:team, WorkerTeam, bindings: %{events: :cell})
             |> Builder.build()

    assert {:error, _} =
             base
             |> Builder.include(:team, WorkerTeam,
               bindings: [%{key: :events, to: :bus}, %{key: "events", to: :bus}]
             )
             |> Builder.build()

    assert {:error, _} = WorkerTeam.new(id: "unbound")
  end

  test "export aliases are unique and must refer to an existing endpoint" do
    base = Builder.new(name: "exports") |> Builder.agent(:cell, Cell)

    assert {:error, _} =
             base |> Builder.export(:agent, :public, from: :missing) |> Builder.build()

    assert {:error, _} = base |> Builder.export(:bus, :public, from: :cell) |> Builder.build()

    assert {:error, _} =
             base
             |> Builder.export(:agent, :public, from: :cell)
             |> Builder.export(:agent, :public, from: :cell)
             |> Builder.build()
  end

  test "cycles and duplicate ownership are checked across inclusion boundaries" do
    base =
      Builder.new(name: "cycles")
      |> Builder.bus(:bus)
      |> Builder.include(:east, WorkerTeam, bindings: %{events: :bus})
      |> Builder.include(:west, WorkerTeam, bindings: %{events: :bus})

    assert {:error, error} =
             base
             |> Builder.owns(Ref.ref(:east, :leader), Ref.ref(:west, :leader))
             |> Builder.owns(Ref.ref(:west, :leader), Ref.ref(:east, :leader))
             |> Builder.build()

    assert Exception.message(error) =~ "cycle"

    assert {:error, _} =
             base
             |> Builder.owns(Ref.ref(:west, :leader), Ref.ref(:east, :workers))
             |> Builder.build()
  end

  test "import and export cycles fail without starting processes" do
    unit =
      Builder.new(name: "unit")
      |> Builder.import_bus(:bus)
      |> Builder.export(:bus, :bus, from: :bus)
      |> Builder.build!()

    assert {:error, error} =
             Builder.new(name: "loop")
             |> Builder.include(:a, unit, bindings: %{bus: Ref.ref(:b, :bus)})
             |> Builder.include(:b, unit, bindings: %{bus: Ref.ref(:a, :bus)})
             |> Builder.build()

    assert Exception.message(error) =~ "cycle"
  end

  test "root and child Agent limits apply to the full expanded subtree" do
    assert {:error, _} =
             ComposedFormats.builder()
             |> Builder.startup(max_agents: 7)
             |> Builder.build(id: "limit")

    child = Builder.new(WorkerTeam) |> Builder.startup(max_agents: 2) |> Builder.build!()

    assert {:error, _} =
             Builder.new(name: "limit")
             |> Builder.bus(:bus)
             |> Builder.include(:team, child,
               inputs: %{worker_count: 2},
               bindings: %{events: :bus}
             )
             |> Builder.build(id: "child-limit")
  end

  test "child schemas validate mapped input and report the component path" do
    assert {:error, error} =
             ComposedSystem.new(id: "bad", input: %{east_workers: 1, west_workers: 1.5})

    assert Exception.message(error) =~ "input"

    assert {:error, error} =
             Builder.new(name: "bad-child")
             |> Builder.bus(:bus)
             |> Builder.include(:team, WorkerTeam,
               inputs: %{worker_count: -1},
               bindings: %{events: :bus}
             )
             |> Builder.build(id: "bad")

    assert Exception.message(error) =~ "included topology input"
  end

  test "structured addresses preserve separators and inclusion order does not change the plan" do
    base = Builder.new(name: "names") |> Builder.bus(:bus)

    definition =
      base
      |> Builder.include("east/west", WorkerTeam, bindings: %{events: :bus})
      |> Builder.include("east", WorkerTeam, bindings: %{events: :bus})
      |> Builder.build!()

    reversed = %{definition | includes: Enum.reverse(definition.includes)}
    {:ok, first} = Topology.instantiate(definition, id: "names")
    {:ok, second} = Topology.instantiate(reversed, id: "names")
    assert first.plan == second.plan
    assert first.plan.agents["component/east%2Fwest/agent/coordinator"]
    assert first.plan.agents["component/east/agent/coordinator"]
  end

  test "root instance names cannot collide with component paths" do
    composed = ComposedSystem.new!(id: "root")

    leaf =
      Builder.new(name: "leaf")
      |> Builder.agent(:coordinator, Cell)
      |> Builder.build!(id: "root/component/east")

    assert composed.plan.agents["component/east/agent/coordinator"].id !=
             leaf.plan.agents["agent/coordinator"].id

    assert leaf.plan.agents["agent/coordinator"].id == "root%2Fcomponent%2Feast/agent/coordinator"
  end

  test "recursive modules and excessive nesting return structured errors" do
    assert {:error, error} =
             Builder.new(name: "root")
             |> Builder.include(:loop, RecursiveSource)
             |> Builder.build()

    assert Exception.message(error) =~ "Recursive"

    source =
      Enum.reduce(1..34, %{name: "leaf"}, fn _, child ->
        %{name: "nested", includes: [%{key: :child, topology: child}]}
      end)

    assert {:error, error} = Topology.new(source)
    assert Exception.message(error) =~ "depth"
  end

  test "Codec rejects changes to nested topology and export reference records" do
    {:ok, document} = Codec.encode(ComposedSystem.topology(), ComposedFormats.registry())
    [east, west] = document["includes"]
    bad = put_in(east, ["topology", "version"], 99)

    assert {:error, _} =
             Codec.decode(%{document | "includes" => [bad, west]}, ComposedFormats.registry())

    [ownership | rest] = document["relationships"]
    malformed = put_in(ownership, ["child", "key"], 42)

    assert {:error, _} =
             Codec.decode(
               %{document | "relationships" => [malformed | rest]},
               ComposedFormats.registry()
             )
  end
end

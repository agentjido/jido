defmodule Jido.Topology.CompositionTest do
  use ExUnit.Case, async: true
  alias Jido.Examples.Topology.{Cell, ComposedFormats, ComposedSystem, WorkerTeam}
  alias Jido.Topology
  alias Jido.Topology.{Codec, Plan, Ref, Reference}

  defmodule RecursiveSource do
    def __topology_config__ do
      %{name: "recursive", includes: [%{key: "again", topology: __MODULE__}]}
    end
  end

  test "DSL, data, and stored JSON retain the same composition and plan" do
    definition = ComposedSystem.topology()
    assert {:ok, ^definition} = Jido.Topology.new(ComposedFormats.data())
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

    assert {:ok, ^instance} =
             (with {:ok, definition} <- Jido.Topology.new(ComposedFormats.data()) do
                Jido.Topology.instantiate(definition, id: "composed")
              end)

    assert map_size(instance.plan.agents) == 8
    assert map_size(instance.plan.resources) == 1
    assert instance.definition.startup.concurrency == 4
  end

  test "direct Plan construction equals instance planning with normalized input" do
    for input <- [%{east_workers: 0, west_workers: 2}, %{east_workers: 3, west_workers: 1}] do
      instance = ComposedSystem.new!(id: "direct/plan", input: input)
      assert {:ok, plan} = Plan.build(instance.definition, instance.id, instance.input)
      assert plan == instance.plan
    end
  end

  test "instance validation keeps graph, options, input, and root import error order" do
    definition = WorkerTeam.topology()
    invalid = %{definition | exports: [%{key: "missing", kind: :agent, from: "missing"}]}
    assert {:error, graph_error} = Topology.new(invalid)
    assert {:error, instance_error} = Topology.instantiate(invalid, unexpected: true)
    assert Map.drop(instance_error, [:stacktrace]) == Map.drop(graph_error, [:stacktrace])

    assert {:error, opts_error} = Topology.instantiate(definition, unexpected: true)
    assert Exception.message(opts_error) =~ "Unknown"

    assert {:error, input_error} =
             Topology.instantiate(definition, id: "root", input: %{worker_count: -1})

    assert Exception.message(input_error) =~ "input"

    assert {:error, root_error} = Topology.instantiate(definition, id: "root")
    assert Exception.message(root_error) =~ "unbound imports"
    assert {:error, plan_error} = Plan.build(invalid, "root", %{})
    assert Map.drop(plan_error, [:stacktrace]) == Map.drop(root_error, [:stacktrace])
  end

  test "direct Plan construction still checks the declaration graph" do
    definition =
      Jido.Topology.new!(%{name: "cycle", groups: [%{key: :workers, module: Cell, count: 0}]})

    [group] = definition.groups
    invalid = %{definition | groups: [%{group | depends_on: ["workers"]}]}

    assert {:error, error} = Plan.build(invalid, "cycle", %{})
    assert Exception.message(error) =~ "cycle"
    assert {:error, instance_error} = Topology.instantiate(invalid, id: "cycle")
    assert Map.drop(instance_error, [:stacktrace]) == Map.drop(error, [:stacktrace])
  end

  test "inputs and identities are isolated while Bus bindings share one owner" do
    instance = ComposedSystem.new!(id: "system", input: %{east_workers: 1, west_workers: 2})
    east = instance.plan.agents["component/east/group/workers/1"]
    west = instance.plan.agents["component/west/group/workers/1"]
    assert east.id != west.id
    assert east.initial_state.label == "east"
    assert west.initial_state.label == "west"
    assert east.subscriptions == west.subscriptions
    assert east.subscriptions == [%{bus: "bus/events", path: "examples.topology.cell.work"}]
    assert east.parent == "component/east/agent/coordinator"
    assert instance.plan.agents[east.parent].parent == "agent/director"
    assert instance.plan.components[["east"]].agents == 2
    assert instance.plan.components[["east"]].resources == 0
  end

  test "nested topologies can re-export public endpoints" do
    region =
      Jido.Topology.new!(%{
        schema: Zoi.object(%{count: Zoi.integer() |> Zoi.default(2)}),
        name: "region",
        imports: [%{key: :events, kind: :bus}],
        includes: [
          %{
            key: :team,
            topology: WorkerTeam,
            inputs: %{worker_count: Reference.input(:count)},
            bindings: %{events: :events}
          }
        ],
        exports: [
          %{kind: :agent, key: :leader, from: Ref.ref(:team, :leader)},
          %{kind: :group, key: :workers, from: Ref.ref(:team, :workers)}
        ]
      })

    root =
      Jido.Topology.new!(%{
        name: "root",
        resources: [%{key: :bus, kind: :bus}],
        includes: [
          %{key: :region, topology: region, inputs: %{count: 3}, bindings: %{events: :bus}}
        ]
      })

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
    base = ComposedFormats.data()

    assert {:error, _} =
             Jido.Topology.new(
               Map.update(
                 base,
                 :relationships,
                 [%{parent: :director, child: Ref.ref(:east, :coordinator)}],
                 &(&1 ++ [%{parent: :director, child: Ref.ref(:east, :coordinator)}])
               )
             )

    assert {:error, _} =
             Jido.Topology.new(
               Map.update(
                 base,
                 :relationships,
                 [%{parent: Ref.ref(:east, :workers), child: :director}],
                 &(&1 ++ [%{parent: Ref.ref(:east, :workers), child: :director}])
               )
             )

    assert {:error, _} =
             Jido.Topology.new(
               Map.update(
                 base,
                 :connections,
                 [%{agent: :director, to: Ref.ref(:east, :leader), path: "**"}],
                 &(&1 ++ [%{agent: :director, to: Ref.ref(:east, :leader), path: "**"}])
               )
             )

    plan = ComposedSystem.new!(id: "private").plan
    assert Plan.resolve(plan, Ref.ref(:east, :coordinator), :agent) == nil

    assert Plan.resolve(plan, Ref.ref(:east, :leader), :agent) ==
             "component/east/agent/coordinator"
  end

  test "imports require exact bindings and correct resource kinds" do
    base = %{
      name: "imports",
      resources: [%{key: :bus, kind: :bus}],
      agents: [%{key: :cell, module: Cell}]
    }

    assert {:error, _} =
             Jido.Topology.new(
               Map.update(
                 base,
                 :includes,
                 [%{key: :team, topology: WorkerTeam}],
                 &(&1 ++ [%{key: :team, topology: WorkerTeam}])
               )
             )

    assert {:error, _} =
             Jido.Topology.new(
               Map.update(
                 base,
                 :includes,
                 [%{key: :team, topology: WorkerTeam, bindings: %{events: :bus, extra: :bus}}],
                 &(&1 ++
                     [%{key: :team, topology: WorkerTeam, bindings: %{events: :bus, extra: :bus}}])
               )
             )

    assert {:error, _} =
             Jido.Topology.new(
               Map.update(
                 base,
                 :includes,
                 [%{key: :team, topology: WorkerTeam, bindings: %{events: :cell}}],
                 &(&1 ++ [%{key: :team, topology: WorkerTeam, bindings: %{events: :cell}}])
               )
             )

    assert {:error, _} =
             Jido.Topology.new(
               Map.update(
                 base,
                 :includes,
                 [
                   %{
                     key: :team,
                     topology: WorkerTeam,
                     bindings: [%{key: :events, to: :bus}, %{key: "events", to: :bus}]
                   }
                 ],
                 &(&1 ++
                     [
                       %{
                         key: :team,
                         topology: WorkerTeam,
                         bindings: [%{key: :events, to: :bus}, %{key: "events", to: :bus}]
                       }
                     ])
               )
             )

    assert {:error, _} = WorkerTeam.new(id: "unbound")
  end

  test "export aliases are unique and must refer to an existing endpoint" do
    base = %{name: "exports", agents: [%{key: :cell, module: Cell}]}

    assert {:error, _} =
             Jido.Topology.new(
               Map.update(
                 base,
                 :exports,
                 [%{kind: :agent, key: :public, from: :missing}],
                 &(&1 ++ [%{kind: :agent, key: :public, from: :missing}])
               )
             )

    assert {:error, _} =
             Jido.Topology.new(
               Map.update(
                 base,
                 :exports,
                 [%{kind: :bus, key: :public, from: :cell}],
                 &(&1 ++ [%{kind: :bus, key: :public, from: :cell}])
               )
             )

    assert {:error, _} =
             Jido.Topology.new(
               Map.update(
                 Map.update(
                   base,
                   :exports,
                   [%{kind: :agent, key: :public, from: :cell}],
                   &(&1 ++ [%{kind: :agent, key: :public, from: :cell}])
                 ),
                 :exports,
                 [%{kind: :agent, key: :public, from: :cell}],
                 &(&1 ++ [%{kind: :agent, key: :public, from: :cell}])
               )
             )
  end

  test "cycles and duplicate ownership are checked across inclusion boundaries" do
    base =
      %{
        name: "cycles",
        resources: [%{key: :bus, kind: :bus}],
        includes: [
          %{key: :east, topology: WorkerTeam, bindings: %{events: :bus}},
          %{key: :west, topology: WorkerTeam, bindings: %{events: :bus}}
        ]
      }

    assert {:error, error} =
             Jido.Topology.new(
               Map.update(
                 Map.update(
                   base,
                   :relationships,
                   [%{parent: Ref.ref(:east, :leader), child: Ref.ref(:west, :leader)}],
                   &(&1 ++ [%{parent: Ref.ref(:east, :leader), child: Ref.ref(:west, :leader)}])
                 ),
                 :relationships,
                 [%{parent: Ref.ref(:west, :leader), child: Ref.ref(:east, :leader)}],
                 &(&1 ++ [%{parent: Ref.ref(:west, :leader), child: Ref.ref(:east, :leader)}])
               )
             )

    assert Exception.message(error) =~ "cycle"

    assert {:error, _} =
             Jido.Topology.new(
               Map.update(
                 base,
                 :relationships,
                 [%{parent: Ref.ref(:west, :leader), child: Ref.ref(:east, :workers)}],
                 &(&1 ++ [%{parent: Ref.ref(:west, :leader), child: Ref.ref(:east, :workers)}])
               )
             )
  end

  test "import and export cycles fail without starting processes" do
    unit =
      Jido.Topology.new!(%{
        name: "unit",
        imports: [%{key: :bus, kind: :bus}],
        exports: [%{kind: :bus, key: :bus, from: :bus}]
      })

    assert {:error, error} =
             Jido.Topology.new(%{
               name: "loop",
               includes: [
                 %{key: :a, topology: unit, bindings: %{bus: Ref.ref(:b, :bus)}},
                 %{key: :b, topology: unit, bindings: %{bus: Ref.ref(:a, :bus)}}
               ]
             })

    assert Exception.message(error) =~ "cycle"
  end

  test "root and child Agent limits apply to the full expanded subtree" do
    assert {:error, _} =
             (with {:ok, definition} <-
                     Jido.Topology.new(Map.put(ComposedFormats.data(), :startup, max_agents: 7)) do
                Jido.Topology.instantiate(definition, id: "limit")
              end)

    child = Jido.Topology.new!(Map.put(WorkerTeam.topology(), :startup, max_agents: 2))

    assert {:error, _} =
             (with {:ok, definition} <-
                     Jido.Topology.new(%{
                       name: "limit",
                       resources: [%{key: :bus, kind: :bus}],
                       includes: [
                         %{
                           key: :team,
                           topology: child,
                           inputs: %{worker_count: 2},
                           bindings: %{events: :bus}
                         }
                       ]
                     }) do
                Jido.Topology.instantiate(definition, id: "child-limit")
              end)
  end

  test "Agent limits fail before member and Agent state transformations" do
    assert {:error, member_error} =
             (with {:ok, definition} <-
                     Jido.Topology.new(%{
                       startup: [max_agents: 1],
                       name: "member-limit",
                       groups: [
                         %{
                           key: :workers,
                           module: Cell,
                           members: [%{}, %{id: "valid"}],
                           key_by: :id
                         }
                       ]
                     }) do
                Jido.Topology.instantiate(definition, id: "member-limit")
              end)

    assert Exception.message(member_error) =~ "max_agents"

    child =
      Jido.Topology.new!(%{
        startup: [max_agents: 1],
        name: "invalid-child",
        agents: [
          %{key: :invalid, module: Cell, initial_state: %{total: "invalid"}},
          %{key: :valid, module: Cell}
        ]
      })

    assert {:error, child_error} =
             (with {:ok, definition} <-
                     Jido.Topology.new(%{
                       name: "parent",
                       includes: [%{key: :child, topology: child}]
                     }) do
                Jido.Topology.instantiate(definition, id: "child-limit-order")
              end)

    assert Exception.message(child_error) =~ "max_agents"
  end

  test "child schemas validate mapped input and report the component path" do
    assert {:error, error} =
             ComposedSystem.new(id: "bad", input: %{east_workers: 1, west_workers: 1.5})

    assert Exception.message(error) =~ "input"

    assert {:error, error} =
             (with {:ok, definition} <-
                     Jido.Topology.new(%{
                       name: "bad-child",
                       resources: [%{key: :bus, kind: :bus}],
                       includes: [
                         %{
                           key: :team,
                           topology: WorkerTeam,
                           inputs: %{worker_count: -1},
                           bindings: %{events: :bus}
                         }
                       ]
                     }) do
                Jido.Topology.instantiate(definition, id: "bad")
              end)

    assert Exception.message(error) =~ "included topology input"
  end

  test "structured addresses preserve separators and inclusion order does not change the plan" do
    base = %{name: "names", resources: [%{key: :bus, kind: :bus}]}

    definition =
      Jido.Topology.new!(
        Map.update(
          Map.update(
            base,
            :includes,
            [%{key: "east/west", topology: WorkerTeam, bindings: %{events: :bus}}],
            &(&1 ++ [%{key: "east/west", topology: WorkerTeam, bindings: %{events: :bus}}])
          ),
          :includes,
          [%{key: "east", topology: WorkerTeam, bindings: %{events: :bus}}],
          &(&1 ++ [%{key: "east", topology: WorkerTeam, bindings: %{events: :bus}}])
        )
      )

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
      Jido.Topology.unwrap!(
        with {:ok, definition} <-
               Jido.Topology.new(%{name: "leaf", agents: [%{key: :coordinator, module: Cell}]}) do
          Jido.Topology.instantiate(definition, id: "root/component/east")
        end
      )

    assert composed.plan.agents["component/east/agent/coordinator"].id !=
             leaf.plan.agents["agent/coordinator"].id

    assert leaf.plan.agents["agent/coordinator"].id == "root%2Fcomponent%2Feast/agent/coordinator"
  end

  test "recursive modules and excessive nesting return structured errors" do
    assert {:error, error} =
             Jido.Topology.new(%{
               name: "root",
               includes: [%{key: :loop, topology: RecursiveSource}]
             })

    assert Exception.message(error) =~ "Recursive"

    source =
      Enum.reduce(1..34, %{name: "leaf"}, fn _, child ->
        %{name: "nested", includes: [%{key: :child, topology: child}]}
      end)

    assert {:error, error} = Topology.new(source)
    assert Exception.message(error) =~ "depth"
  end

  test "composition accepts 1000 scopes and rejects scope 1001" do
    leaf = Jido.Topology.new!(%{name: "leaf"})

    attrs = %{
      name: "scope-limit",
      includes: for(index <- 1..999, do: %{key: "scope-#{index}", topology: leaf})
    }

    assert {:ok, topology} = Jido.Topology.new(attrs)

    assert Enum.map(topology.includes, & &1.key) ==
             Enum.map(1..999, &"scope-#{&1}")

    assert {:error,
            %Jido.Error.ValidationError{
              message: "Topology exceeds 1000 component scopes"
            }} =
             Jido.Topology.new(
               Map.update(
                 attrs,
                 :includes,
                 [%{key: "scope-1000", topology: leaf}],
                 &(&1 ++ [%{key: "scope-1000", topology: leaf}])
               )
             )
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

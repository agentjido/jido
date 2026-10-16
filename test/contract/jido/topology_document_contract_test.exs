defmodule JidoTest.Contract.TopologyDocumentTest do
  use Covenant.Case, component: "jido.topology", async: false

  alias Jido.Codec.Registry
  alias Jido.Topology
  alias Jido.Topology.{Codec, Ref, Reference}
  alias Jido.Error.ValidationError
  alias JidoTest.TopologyContract, as: T

  @tag obligation: ["jido.topology.I7", "jido.topology.I16"]
  test "version 2 module documents and version 3 neutral members retain definitions and plans" do
    for {entry, version} <- [
          {%{key: :worker, module: JidoTest.AgentFixtures.CounterAgent}, 2},
          {%{key: :worker, definition: T.worker(), initial_state: %{count: 3}}, 3}
        ] do
      definition = Topology.new!(name: "document", agents: [entry], metadata: %{owner: "graph"})
      assert {:ok, document, registry} = Codec.encode(definition)
      assert document["type"] === "jido.topology"
      assert document["version"] === version
      assert {:ok, ^document} = Codec.encode(definition, registry)
      assert {:ok, ^definition} = Topology.new(Map.from_struct(definition))
      assert {:ok, ^definition} = Topology.new(Map.to_list(Map.from_struct(definition)))
      assert {:ok, ^definition} = Codec.decode(JSON.decode!(JSON.encode!(document)), registry)
      assert {:ok, instance} = Topology.instantiate(definition, id: "document")
      assert {:ok, ^instance} = Codec.decode(document, registry, id: "document")

      if version == 2 do
        refute Map.has_key?(document, "children")
        assert {:error, _} = Codec.decode(Map.put(document, "children", []), registry)
      else
        assert {:error, _} = Codec.decode(Map.put(document, "version", 2), registry)
      end
    end
  end

  @tag obligation: ["jido.topology.I16", "jido.topology.I15"]
  test "document decoding requires supported versions, strict fields, and trusted Registry kinds" do
    definition =
      Topology.new!(
        name: "registry",
        agents: [%{key: :worker, module: JidoTest.AgentFixtures.CounterAgent}]
      )

    assert {:ok, document, registry} = Codec.encode(definition)
    [agent] = document["agents"]

    for invalid <- [
          Map.put(document, "type", "unknown"),
          Map.put(document, "version", 999),
          Map.put(document, "runtime", %{}),
          Map.put(document, "agents", nil),
          Map.put(document, "agents", [Map.put(agent, "unknown", true)]),
          Map.put(document, "agents", [Map.put(agent, "module", document["schema"])]),
          Map.put(document, "agents", [Map.put(agent, "module", "untrusted/module")])
        ] do
      assert {:error, %ValidationError{} = expected} = Codec.decode(invalid, registry)

      assert {:error, %ValidationError{} = actual} =
               Codec.decode(invalid, registry, unknown: true)

      assert actual.message == expected.message
      assert actual.details == expected.details
    end

    assert {:error, _} = Codec.decode(document, %{})
    assert {:error, _} = Codec.encode(definition, %{})

    invalid_registry = %{"invalid" => :invalid}
    assert {:error, %ValidationError{} = expected} = Jido.Codec.Registry.new(invalid_registry)

    assert {:error, %ValidationError{} = actual} =
             Codec.decode(Map.put(document, "version", 999), invalid_registry, unknown: true)

    assert actual.message == expected.message
    assert actual.details == expected.details
  end

  @tag obligation: [
         "jido.topology.I6",
         "jido.topology.I9",
         "jido.topology.I14",
         "jido.topology.I16"
       ]
  test "instance decoding resolves current source contracts once per operation" do
    assert {:ok, document, registry} =
             Codec.encode(%{
               name: "resolved_document",
               agents: [%{key: :leader, module: T.ObservedAgent}],
               groups: [%{key: :workers, module: T.ObservedAgent, count: 2}]
             })

    assert_received :read_planning_agent
    assert_received :read_planning_plugin

    for _ <- 1..2 do
      assert {:ok, instance} = Codec.decode(document, registry, id: "resolved_document")
      assert_receive :read_planning_agent
      assert_receive :read_planning_plugin
      refute_received :read_planning_agent
      refute_received :read_planning_plugin
      assert map_size(instance.plan.agents) == 3
      assert Enum.sort(Map.keys(instance.plan.resources)) == ["bus/leader_bus", "bus/workers_bus"]
    end
  end

  @tag obligation: ["jido.topology.I13", "jido.topology.I15", "jido.topology.I16"]
  test "instance decoding rejects static graph faults before contributions and instance options" do
    definition =
      Topology.new!(
        name: "ordered_document",
        agents: [%{key: :worker, definition: T.worker([T.Audit])}],
        resources: [%{key: :events}],
        connections: [%{agent: :worker, to: :events, path: "contract.**"}]
      )

    assert {:ok, document, registry} = Codec.encode(definition)
    invalid = %{document | "resources" => []}
    assert {:error, %ValidationError{} = expected} = Codec.decode(invalid, registry)
    assert {:error, %ValidationError{} = actual} = Codec.decode(invalid, registry, unknown: true)
    assert actual.message == expected.message
    assert actual.details == expected.details
    refute_received {:contributed, _, _}

    assert {:error, %ValidationError{}} = Codec.decode(document, registry, unknown: true)
    assert_received {:contributed, T.Audit, "worker"}
  end

  @tag obligation: "jido.topology.I16"
  test "both encoding paths and decoding enforce bounds and exclude instance data" do
    definition = Topology.new!(name: "bounded")
    assert {:ok, document, registry} = Codec.encode(definition)

    for value <- [
          String.duplicate("x", 1_048_577),
          List.duplicate(0, 10_001),
          Enum.reduce(1..102, nil, fn _, nested -> [nested] end)
        ] do
      assert {:error, _} = Codec.encode(%{definition | metadata: %{"large" => value}})
      assert {:error, _} = Codec.encode(%{definition | metadata: %{"large" => value}}, registry)

      bounded =
        Map.put(document, "metadata", %{"$type" => "map", "entries" => [["large", value]]})

      assert {:error, %ValidationError{} = expected} = Codec.decode(bounded, registry)

      assert {:error, %ValidationError{} = actual} =
               Codec.decode(bounded, registry, unknown: true)

      assert actual.message == expected.message
      assert actual.details == expected.details
    end

    assert {:ok, instance} = Topology.instantiate(definition, id: "private")
    assert {:error, _} = Codec.encode(instance)
    for field <- ~w(id input plan state status), do: refute(Map.has_key?(document, field))
    assert {:error, _} = Codec.encode(%{definition | metadata: %{pid: self()}})
    assert {:error, _} = Codec.encode(%{definition | metadata: %{pid: self()}}, registry)
  end

  @tag obligation: ["jido.topology.I16", "jido.topology.I12"]
  test "stored includes and references retain their scopes and exact plan" do
    leaf =
      Topology.new!(
        name: "leaf",
        schema: Zoi.object(%{count: Zoi.integer()}),
        groups: [
          %{
            key: :workers,
            definition: T.worker(),
            count: Reference.input(:count),
            initial_state: %{count: Reference.member(:index)}
          }
        ],
        exports: [%{key: :workers, kind: :group, from: :workers}]
      )

    root =
      Topology.new!(
        name: "root",
        includes: [%{key: :leaf, topology: leaf, inputs: %{count: 2}}],
        metadata: %{
          Reference.input(:count) => %{
            "nested" => {Ref.ref(:leaf, :workers), [Reference.member(:index), %{flag: false}]}
          }
        }
      )

    assert {:ok, document, registry} = Codec.encode(root)
    assert {:ok, ^root} = Codec.decode(JSON.decode!(JSON.encode!(document)), registry)
    assert {:ok, instance} = Topology.instantiate(root, id: "root")
    assert {:ok, ^instance} = Codec.decode(document, registry, id: "root")

    assert instance.plan.layers === [
             ["component/leaf/group/workers/1", "component/leaf/group/workers/2"]
           ]
  end

  @tag obligation: ["jido.topology.I15", "jido.topology.I16"]
  test "nested tagged maps reject decoded key collisions and preserve reference errors" do
    definition = Topology.new!(name: "nested_maps", metadata: %{same: 0})
    assert {:ok, document, registry} = Codec.encode(definition)
    assert {:ok, canonical} = Registry.identifier(registry, :atom, :same)
    registry = Registry.new!(Map.put(registry.entries, "aliases/same", {:alias, canonical}))

    duplicate = %{
      "$type" => "map",
      "entries" => [
        [%{"$type" => "atom", "id" => canonical}, 1],
        [%{"$type" => "atom", "id" => "aliases/same"}, 2]
      ]
    }

    invalid_references = [
      %{"$type" => "topology.input", "key" => false},
      %{"$type" => "topology.ref", "component" => "", "key" => "worker"}
    ]

    assert {:error, %ValidationError{} = collision} =
             Codec.decode(%{document | "metadata" => duplicate}, registry)

    assert collision.message == "Duplicate decoded map key"

    cases =
      [{duplicate, collision}] ++
        Enum.map(invalid_references, fn encoded ->
          assert {:error, %ValidationError{} = expected} =
                   Codec.decode(%{document | "metadata" => encoded}, registry)

          refute {expected.message, expected.details} == {collision.message, collision.details}
          {encoded, expected}
        end)

    for {value, expected} <- cases do
      nested = %{"$type" => "map", "entries" => [["nested", value]]}
      invalid = %{document | "metadata" => nested}

      for result <- [
            Codec.decode(invalid, registry),
            Codec.decode(invalid, registry, unknown: true)
          ] do
        assert {:error, %ValidationError{} = actual} = result
        assert actual.message == expected.message
        assert actual.details == expected.details
      end
    end
  end

  @tag obligation: "jido.topology.I17"
  test "child declarations retain directors and validate resolved command members and event targets" do
    leaf = %{
      name: "leaf",
      schema: Zoi.object(%{count: Zoi.integer()}),
      groups: [%{key: :workers, definition: T.worker(), count: Reference.input(:count)}]
    }

    child = %{
      key: :leaf,
      topology: leaf,
      director: T.worker(),
      activation: :deferred,
      input: %{count: Reference.input(:count)},
      max_restarts: 2,
      max_seconds: 4,
      gate: %{
        commands: [%{type: "contract.run", member: {:group, :workers, "2"}}],
        events: ["public.**"],
        to: :events
      }
    }

    definition =
      Topology.new!(
        name: "root",
        schema: Zoi.object(%{count: Zoi.integer()}),
        children: [child],
        resources: [%{key: :events}]
      )

    assert [normalized] = definition.children
    assert normalized.director === T.worker()
    assert normalized.activation === :deferred
    assert normalized.max_restarts === 2 and normalized.max_seconds === 4

    assert {:error, %ValidationError{}} =
             Topology.instantiate(definition, id: "small", input: %{count: 1})

    assert {:ok, instance} = Topology.instantiate(definition, id: "two", input: %{count: 2})
    assert instance.plan.agents === %{}
    assert {:ok, %{"version" => 3} = document, registry} = Codec.encode(definition)
    assert {:ok, ^definition} = Codec.decode(JSON.decode!(JSON.encode!(document)), registry)
    assert {:ok, ^instance} = Codec.decode(document, registry, id: "two", input: %{count: 2})
    assert {:error, _} = Codec.decode(Map.put(document, "version", 2), registry)

    for update <- [
          %{activation: :invalid},
          %{max_restarts: -1},
          %{max_seconds: 0},
          %{gate: %{commands: [%{type: "contract.*", member: {:group, :workers, "2"}}]}},
          %{gate: %{events: ["public.**"]}}
        ] do
      assert {:error, %ValidationError{}} =
               Topology.new(name: "invalid", children: [Map.merge(child, update)])
    end

    bad_bus = put_in(child.gate.to, :missing)

    assert {:error, _} =
             Topology.instantiate(%{name: "bad_bus", children: [bad_bus]},
               id: "bad",
               input: %{count: 2}
             )

    assert {:error, %ValidationError{}} =
             Topology.new(name: "include", includes: [%{key: :root, topology: definition}])
  end

  @tag obligation: ["jido.topology.I12", "jido.topology.I15", "jido.topology.I17"]
  test "recursive module providers report include and child cycles before the depth limit" do
    for {field, message} <- [
          includes: "Recursive topology inclusion",
          children: "Child topology cycle"
        ] do
      module = Module.concat(__MODULE__, "Cycle#{System.unique_integer([:positive])}")

      JidoTest.AuthoringCompiler.with_compiled(
        """
        defmodule #{inspect(module)} do
          def __topology_config__ do
            [name: "recursive", #{field}: [%{key: :again, topology: __MODULE__}]]
          end
        end
        """,
        fn _ ->
          assert {:error, %ValidationError{} = error} =
                   Topology.new(%{field => [%{key: :first, topology: module}], :name => "parent"})

          assert error.message == message
          assert error.details.module == module
          assert Enum.take(error.details.source_path, 2) == [field, 0]
        end,
        modules: [module]
      )
    end
  end

  @tag obligation: ["jido.topology.I12", "jido.topology.I17"]
  test "legacy graph providers are runtime children only and do not infer an owner" do
    module = Module.concat(__MODULE__, "Legacy#{System.unique_integer([:positive])}")

    JidoTest.AuthoringCompiler.with_compiled(
      "defmodule #{inspect(module)} do\ndef topology, do: [name: \"legacy\"]\nend",
      fn _ ->
        assert {:ok, definition} =
                 Topology.new(name: "parent", children: [%{key: :legacy, topology: module}])

        assert [child] = definition.children
        assert child.topology.name == "legacy"
        assert child.director == nil

        assert {:error, %ValidationError{}} =
                 Topology.new(name: "parent", includes: [%{key: :legacy, topology: module}])
      end,
      modules: [module]
    )
  end

  @tag obligation: ["jido.topology.I15", "jido.topology.I17"]
  test "source provider faults retain their causes for includes and children" do
    T.with_topology("", fn module ->
      definition = Topology.new!(name: "source", includes: [%{key: :source, topology: module}])
      assert hd(definition.includes).topology === module.topology()
    end)

    for kind <- [:error, :throw, :exit] do
      module = Module.concat(__MODULE__, "Source#{System.unique_integer([:positive])}")

      expression =
        case kind do
          :error -> "raise(ArgumentError, \"source failure\")"
          :throw -> "throw(:source_failure)"
          :exit -> "exit(:source_failure)"
        end

      JidoTest.AuthoringCompiler.with_compiled(
        "defmodule #{inspect(module)} do\ndef __topology_config__, do: #{expression}\nend",
        fn _ ->
          for field <- [:includes, :children] do
            assert {:error, %ValidationError{} = error} =
                     Topology.new(%{
                       field => [%{key: :source, topology: module}],
                       :name => "source"
                     })

            assert error.details.module === module
            assert error.details.kind === kind
            assert error.details.source_path === [field, 0, :topology]

            assert error.details.reason ===
                     if(kind == :error,
                       do: %ArgumentError{message: "source failure"},
                       else: :source_failure
                     )
          end
        end,
        modules: [module]
      )
    end
  end
end

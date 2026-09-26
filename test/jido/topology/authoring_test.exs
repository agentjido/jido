defmodule JidoTest.Topology.InvalidSourceLocatedTopology do
  def __topology_config__ do
    config = Jido.Examples.Topology.Swarm.__topology_config__()
    [agent] = config.agents
    %{config | agents: [%{agent | module: String}]}
  end

  def __topology_sources__, do: Jido.Examples.Topology.Swarm.__topology_sources__()
end

defmodule Jido.Topology.AuthoringTest do
  use ExUnit.Case, async: true

  alias Jido.Examples.Topology.{Accounts, Cell, Formats, Swarm}
  alias Jido.Topology
  alias Jido.Topology.{Codec, Plan, Ref, Reference}

  test "a large group plan keeps resource order and ownership" do
    assert {:ok, instance} = Swarm.new(id: "demo", input: %{worker_count: 1_000})
    assert map_size(instance.plan.agents) == 1_001

    assert instance.plan.layers |> List.first() |> Enum.member?("bus/work")
    assert instance.plan.agents["group/workers/1000"].parent == "agent/coordinator"
  end

  test "temporary Registry supports nested member and input references" do
    definition = Accounts.topology()
    assert {:ok, document, registry} = Codec.encode(definition)
    assert {:ok, ^definition} = Codec.decode(JSON.decode!(JSON.encode!(document)), registry)
  end

  test "exact node placement survives data, Codec, and plan construction" do
    target_node = :"worker@127.0.0.1"

    attrs =
      %{name: "placed", agents: [%{key: :worker, module: Cell, node: target_node}]}

    assert {:ok, definition} = Jido.Topology.new(attrs)
    assert hd(definition.agents).node == target_node
    assert {:ok, document, registry} = Codec.encode(definition)
    assert {:ok, ^definition} = Codec.decode(JSON.decode!(JSON.encode!(document)), registry)

    assert {:ok, instance} =
             (with {:ok, definition} <- Jido.Topology.new(attrs) do
                Jido.Topology.instantiate(definition, id: "placed")
              end)

    assert instance.plan.agents["agent/worker"].node == target_node
  end

  test "a remote Agent cannot subscribe to a local resource" do
    attrs =
      %{
        name: "remote-resource",
        agents: [%{key: :worker, module: Cell, node: :"worker@127.0.0.1"}],
        resources: [%{key: :events, kind: :bus}],
        connections: [%{agent: :worker, to: :events, path: "examples.topology.cell.work"}]
      }

    assert {:ok, _definition} = Jido.Topology.new(attrs)

    assert {:error, error} =
             (with {:ok, definition} <- Jido.Topology.new(attrs) do
                Jido.Topology.instantiate(definition, id: "remote-resource")
              end)

    assert error.message == "A remote topology Agent cannot subscribe to a local Bus"
  end

  test "every accepted Reference key survives a definition Codec round trip" do
    for reference <- [
          Reference.input(:initial),
          Reference.input("initial"),
          Reference.member(:index),
          Reference.member("index")
        ] do
      definition = Topology.new!(name: "reference-round-trip", metadata: %{reference: reference})
      assert {:ok, document, registry} = Codec.encode(definition)
      assert {:ok, ^definition} = Codec.decode(JSON.decode!(JSON.encode!(document)), registry)
    end
  end

  test "Reference constructors and static validation use the same key contract" do
    for key <- [nil, true, false, "", String.duplicate("x", 256)] do
      assert_raise ArgumentError, fn -> Reference.input(key) end
      assert_raise ArgumentError, fn -> Reference.member(key) end
    end

    for reference <- [
          %Reference{kind: :input, key: ""},
          %Reference{kind: :other, key: :field},
          %Ref{component: "", key: "worker"}
        ] do
      assert {:error, _error} =
               Topology.new(name: "invalid-reference", metadata: %{reference: reference})
    end
  end

  test "keyed identities do not depend on source ordering" do
    accounts = [%{account_id: "a/b", label: "first"}, %{account_id: "c", label: "second"}]
    assert {:ok, first} = Accounts.new(id: "accounts", input: %{accounts: accounts})

    assert {:ok, second} =
             Accounts.new(id: "accounts", input: %{accounts: Enum.reverse(accounts)})

    assert first.plan == second.plan
    assert first.plan.agents["group/accounts/a%2Fb"].initial_state == %{label: "first"}
  end

  test "duplicate member keys and invalid member data fail before startup" do
    assert {:error, _} =
             Accounts.new(
               id: "a",
               input: %{
                 accounts: [%{account_id: "x", label: "A"}, %{account_id: "x", label: "B"}]
               }
             )

    assert {:error, _} = Accounts.new(id: "a", input: %{accounts: [%{label: "A"}]})
  end

  test "zero members produce an empty group and satisfy a dependency" do
    attrs =
      %{
        name: "empty",
        groups: [%{key: :workers, module: Cell, count: 0}],
        agents: [%{key: :observer, module: Cell, depends_on: [:workers]}]
      }

    assert {:ok, instance} =
             (with {:ok, definition} <- Jido.Topology.new(attrs) do
                Jido.Topology.instantiate(definition, id: "empty")
              end)

    assert map_size(instance.plan.agents) == 1
    assert instance.plan.layers == [["agent/observer"]]
  end

  test "count expansion is bounded before allocation" do
    assert {:error, error} = Swarm.new(id: "too-many", input: %{worker_count: 1_000_000_000})
    assert Exception.message(error) =~ "max_agents"
    assert {:error, _} = Swarm.new(id: "bad", input: %{worker_count: -1})
  end

  test "input defaults do not override explicit zero" do
    assert {:ok, instance} = Swarm.new(id: "zero", input: %{worker_count: 0})
    assert instance.input.worker_count == 0
    assert map_size(instance.plan.agents) == 1
  end

  test "identity components cannot collide across agents, groups, or Buses" do
    assert Plan.agent_key("a/b") != Plan.agent_key("a", "b")
    assert Plan.agent_key("a/b", "c") != Plan.agent_key("a", "b/c")
    assert Plan.agent_key("work") != Plan.bus_key("work")
  end

  test "duplicate names, missing references, and cycles fail" do
    base = %{name: "invalid", agents: [%{key: :one, module: Cell}, %{key: :two, module: Cell}]}

    assert {:error, _} =
             Jido.Topology.new(
               Map.update(
                 base,
                 :agents,
                 [%{key: "one", module: Cell}],
                 &(&1 ++ [%{key: "one", module: Cell}])
               )
             )

    assert {:error, _} =
             Jido.Topology.new(
               Map.update(
                 base,
                 :relationships,
                 [%{parent: :missing, child: :one}],
                 &(&1 ++ [%{parent: :missing, child: :one}])
               )
             )

    assert {:error, _} =
             Jido.Topology.new(
               Map.update(
                 Map.update(
                   base,
                   :relationships,
                   [%{parent: :one, child: :two}],
                   &(&1 ++ [%{parent: :one, child: :two}])
                 ),
                 :relationships,
                 [%{parent: :two, child: :one}],
                 &(&1 ++ [%{parent: :two, child: :one}])
               )
             )

    assert {:error, _} =
             Jido.Topology.new(
               Map.update(
                 base,
                 :connections,
                 [%{agent: :one, to: :missing, path: "**"}],
                 &(&1 ++ [%{agent: :one, to: :missing, path: "**"}])
               )
             )

    assert {:error, _} =
             Jido.Topology.new(%{
               name: "cycle",
               agents: [
                 %{key: :one, module: Cell, depends_on: [:two]},
                 %{key: :two, module: Cell, depends_on: [:one]}
               ]
             })
  end

  test "a child has one singleton owner" do
    base =
      %{
        name: "owners",
        agents: [%{key: :one, module: Cell}, %{key: :two, module: Cell}],
        groups: [%{key: :workers, module: Cell}]
      }

    assert {:error, _} =
             Jido.Topology.new(
               Map.update(
                 Map.update(
                   base,
                   :relationships,
                   [%{parent: :one, child: :workers}],
                   &(&1 ++ [%{parent: :one, child: :workers}])
                 ),
                 :relationships,
                 [%{parent: :two, child: :workers}],
                 &(&1 ++ [%{parent: :two, child: :workers}])
               )
             )

    assert {:error, _} =
             Jido.Topology.new(
               Map.update(
                 base,
                 :relationships,
                 [%{parent: :workers, child: :one}],
                 &(&1 ++ [%{parent: :workers, child: :one}])
               )
             )
  end

  test "data constructors reject unknown fields and invalid field values" do
    assert {:error, _} = Topology.new(name: "bad", unknown: true)

    assert {:error, _} =
             Topology.new(name: "bad", agents: [%{key: :a, module: Cell, surprise: true}])

    assert {:error, _} = Topology.new(name: "fields", metadata: self())
    assert {:error, _} = Topology.new(name: "schema", schema: Zoi.integer())
  end

  test "data constructors preserve declaration order at scale" do
    agents = for index <- 1..1_000, do: %{key: "agent-#{index}", module: Cell}
    assert {:ok, definition} = Topology.new(name: "ordered", agents: agents)
    assert Enum.map(definition.agents, & &1.key) == Enum.map(1..1_000, &"agent-#{&1}")
  end

  test "Agent initial state is validated during pure planning" do
    attrs =
      %{name: "state", agents: [%{key: :a, module: Cell, initial_state: %{total: "bad"}}]}

    assert {:ok, _} = Jido.Topology.new(attrs)

    assert {:error, _} =
             (with {:ok, definition} <- Jido.Topology.new(attrs) do
                Jido.Topology.instantiate(definition, id: "state")
              end)
  end

  test "missing input and member references return structured errors" do
    attrs =
      %{name: "refs", groups: [%{key: :g, module: Cell, count: Reference.input(:missing)}]}

    assert {:error, error} =
             (with {:ok, definition} <- Jido.Topology.new(attrs) do
                Jido.Topology.instantiate(definition, id: "missing")
              end)

    assert Exception.message(error) =~ "Missing topology reference"
  end

  test "Codec rejects unknown versions, fields, Registry kinds, and oversized documents" do
    assert {:ok, document} = Codec.encode(Swarm.topology(), Formats.registry())
    assert {:error, _} = Codec.decode(%{document | "version" => 99}, Formats.registry())
    assert {:error, _} = Codec.decode(Map.put(document, "pid", "anything"), Formats.registry())
    [agent] = document["agents"]

    assert {:error, _} =
             Codec.decode(
               %{document | "agents" => [%{agent | "module" => "schemas/swarm"}]},
               Formats.registry()
             )

    assert {:error, _} =
             Codec.decode(
               %{document | "name" => String.duplicate("x", 1_048_577)},
               Formats.registry()
             )

    assert {:error, _} = Codec.decode(%{document | "groups" => nil}, Formats.registry())
  end

  test "both Codec entry points validate definitions before encoding" do
    definition = Swarm.topology()
    invalid = %{definition | metadata: %{pid: self()}}
    assert {:error, error} = Topology.new(invalid)
    assert {:error, derived_error} = Codec.encode(invalid)
    assert {:error, supplied_error} = Codec.encode(invalid, :invalid_registry)
    assert Map.drop(derived_error, [:stacktrace]) == Map.drop(error, [:stacktrace])
    assert Map.drop(supplied_error, [:stacktrace]) == Map.drop(error, [:stacktrace])

    assert {:error, _} = Codec.encode(definition, :invalid_registry)
    assert {:error, _} = Codec.encode(definition, %{})
    assert {:ok, document, registry} = Codec.encode(definition)
    assert document["version"] == 2
    assert {:ok, ^document} = Codec.encode(definition, registry)

    v1 = document |> Map.drop(~w(includes imports exports)) |> Map.put("version", 1)
    assert {:error, _} = Codec.decode(v1, registry)
  end

  test "both Codec entry points retain data and output document bounds" do
    definition = Swarm.topology()
    {:ok, _, registry} = Codec.encode(definition)
    deep = Enum.reduce(1..102, nil, fn _, acc -> [acc] end)

    for value <- [deep, List.duplicate(0, 10_001), String.duplicate("a", 1_048_577)] do
      oversized = %{definition | metadata: %{"value" => value}}
      assert {:error, _} = Codec.encode(oversized)
      assert {:error, _} = Codec.encode(oversized, registry)
    end
  end

  test "Codec excludes instance and runtime data" do
    assert {:ok, instance} = Swarm.new(id: "private", input: %{worker_count: 2})
    assert {:error, _} = Codec.encode(instance)
    assert {:error, _} = Topology.new(name: "runtime", metadata: %{pid: self()})
  end

  test "block metadata accepts mixed keys and rejects structs and runtime values" do
    module = Module.concat(__MODULE__, "Metadata#{System.unique_integer([:positive])}")

    compile_isolated("""
    defmodule #{module} do
      use Jido.Topology, name: "metadata"
      topology do
        metadata %{"owner" => "string", :owner => :atom}
      end
    end
    """)

    assert module.topology().metadata === %{"owner" => "string", :owner => :atom}

    for metadata <- ["~D[2026-09-13]", "%{pid: self()}"] do
      invalid = Module.concat(__MODULE__, "InvalidMetadata#{System.unique_integer([:positive])}")

      assert_raise Spark.Error.DslError, ~r/metadata/, fn ->
        compile_isolated("""
        defmodule #{invalid} do
          use Jido.Topology, name: "invalid_metadata"
          topology do
            metadata #{metadata}
          end
        end
        """)
      end
    end
  end

  test "DSL compile validation rejects cycles and mixed authoring fields" do
    for source <- [
          """
          defmodule JidoTest.InvalidTopologyCycle do
            use Jido.Topology, name: "cycle"
            topology do
              agents do
                agent :a, Jido.Examples.Topology.Cell, depends_on: [:b]
                agent :b, Jido.Examples.Topology.Cell, depends_on: [:a]
              end
            end
          end
          """,
          """
          defmodule JidoTest.InvalidTopologyOverlap do
            use Jido.Topology, name: "overlap", metadata: %{}
            topology do
              metadata %{owner: "test"}
            end
          end
          """
        ] do
      assert_raise CompileError, fn -> compile_isolated(source) end
    end
  end

  test "DSL semantic errors retain the declaration source line" do
    source =
      Enum.find(Swarm.__topology_sources__(), &(&1.field == :agents and &1.index == 0))

    assert source.line > 1
    line = source.line

    error =
      assert_raise CompileError, fn ->
        Jido.Topology.DSL.Compiler.verify(JidoTest.Topology.InvalidSourceLocatedTopology)
      end

    assert error.file == Path.expand(__ENV__.file)
    assert %{description: "Expected an Agent module", line: ^line} = error
  end

  defp compile_isolated(source) do
    {pid, ref} = spawn_monitor(fn -> Code.compile_string(source) end)

    receive do
      {:DOWN, ^ref, :process, ^pid, {error, stack}} -> reraise error, stack
      {:DOWN, ^ref, :process, ^pid, :normal} -> :ok
    after
      10_000 -> flunk("Topology compilation did not finish")
    end
  end
end

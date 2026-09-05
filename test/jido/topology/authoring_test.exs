defmodule Jido.Topology.AuthoringTest do
  use ExUnit.Case, async: true

  alias Jido.Examples.Topology.{Accounts, Cell, Formats, Swarm}
  alias Jido.Topology
  alias Jido.Topology.{Builder, Codec, Plan, Reference}

  test "DSL, Builder, and JSON produce equal definitions and plans" do
    definition = Swarm.topology()
    assert {:ok, ^definition} = Builder.build(Formats.builder())
    assert {:ok, json} = Formats.json()
    assert {:ok, ^definition} = Codec.decode(JSON.decode!(json), Formats.registry())
    assert {:ok, ^definition} = Formats.from_file()
    assert {:ok, instance} = Swarm.new(id: "demo", input: %{worker_count: 1_000})
    assert map_size(instance.plan.agents) == 1_001

    assert {:ok, ^instance} =
             Codec.decode(JSON.decode!(json), Formats.registry(),
               id: "demo",
               input: %{worker_count: 1_000}
             )

    assert {:ok, ^instance} =
             Builder.build(Formats.builder(), id: "demo", input: %{worker_count: 1_000})

    assert instance.plan.layers |> List.first() |> Enum.member?("bus/work")
    assert instance.plan.agents["group/workers/1000"].parent == "agent/coordinator"
  end

  test "temporary Registry supports nested member and input references" do
    definition = Accounts.topology()
    assert {:ok, document, registry} = Codec.encode(definition)
    assert {:ok, ^definition} = Codec.decode(JSON.decode!(JSON.encode!(document)), registry)
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
    builder =
      Builder.new(name: "empty")
      |> Builder.group(:workers, Cell, count: 0)
      |> Builder.agent(:observer, Cell, depends_on: [:workers])

    assert {:ok, instance} = Builder.build(builder, id: "empty")
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
    base = Builder.new(name: "invalid") |> Builder.agent(:one, Cell) |> Builder.agent(:two, Cell)
    assert {:error, _} = base |> Builder.agent("one", Cell) |> Builder.build()
    assert {:error, _} = base |> Builder.owns(:missing, :one) |> Builder.build()

    assert {:error, _} =
             base |> Builder.owns(:one, :two) |> Builder.owns(:two, :one) |> Builder.build()

    assert {:error, _} =
             base |> Builder.subscribe(:one, to: :missing, path: "**") |> Builder.build()

    assert {:error, _} =
             Builder.new(name: "cycle")
             |> Builder.agent(:one, Cell, depends_on: [:two])
             |> Builder.agent(:two, Cell, depends_on: [:one])
             |> Builder.build()
  end

  test "a child has one singleton owner" do
    base =
      Builder.new(name: "owners")
      |> Builder.agent(:one, Cell)
      |> Builder.agent(:two, Cell)
      |> Builder.group(:workers, Cell)

    assert {:error, _} =
             base
             |> Builder.owns(:one, :workers)
             |> Builder.owns(:two, :workers)
             |> Builder.build()

    assert {:error, _} = base |> Builder.owns(:workers, :one) |> Builder.build()
  end

  test "Builder preserves its first error and rejects unknown options" do
    builder = Builder.new(name: "bad") |> Builder.agent(:a, Cell, surprise: true)
    assert {:error, first} = Builder.build(builder)

    assert {:error, ^first} =
             builder |> Builder.bus(:bus) |> Builder.startup(concurrency: 0) |> Builder.build()

    assert {:error, _} = Topology.new(name: "bad", unknown: true)

    assert {:error, _} =
             Builder.new(name: "bad") |> Builder.agent(:a, Cell, key: :b) |> Builder.build()
  end

  test "Builder field errors remain sticky and invalid modules return errors" do
    builder = Builder.new(name: "fields") |> Builder.metadata(self())
    assert {:error, error} = Builder.build(builder)
    assert {:error, ^error} = builder |> Builder.metadata(%{}) |> Builder.build()
    assert {:error, _} = Builder.new(String) |> Builder.build()

    assert {:error, _} =
             Builder.new(name: "schema") |> Builder.schema(Zoi.integer()) |> Builder.build()
  end

  test "Agent initial state is validated during pure planning" do
    builder =
      Builder.new(name: "state") |> Builder.agent(:a, Cell, initial_state: %{total: "bad"})

    assert {:ok, _} = Builder.build(builder)
    assert {:error, _} = Builder.build(builder, id: "state")
  end

  test "missing input and member references return structured errors" do
    builder =
      Builder.new(name: "refs") |> Builder.group(:g, Cell, count: Reference.input(:missing))

    assert {:error, error} = Builder.build(builder, id: "missing")
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
    assert {:error, ^error} = Codec.encode(invalid)
    assert {:error, ^error} = Codec.encode(invalid, :invalid_registry)

    assert {:error, _} = Codec.encode(definition, :invalid_registry)
    assert {:error, _} = Codec.encode(definition, %{})
    assert {:ok, document, registry} = Codec.encode(definition)
    assert document["version"] == 2
    assert {:ok, ^document} = Codec.encode(definition, registry)

    v1 = document |> Map.drop(~w(includes imports exports)) |> Map.put("version", 1)
    assert {:ok, ^definition} = Codec.decode(v1, registry)
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

  test "DSL compile validation rejects cycles and mixed authoring fields" do
    for source <- [
          """
          defmodule JidoTest.InvalidTopologyCycle do
            use Jido.Topology, name: "cycle"
            agents do
              agent :a, Jido.Examples.Topology.Cell, depends_on: [:b]
              agent :b, Jido.Examples.Topology.Cell, depends_on: [:a]
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

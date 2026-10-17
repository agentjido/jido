defmodule JidoTest.Contract.AgentTopologyTest do
  use Covenant.Case, component: "jido.agent", async: true

  alias Jido.Agent
  alias Jido.Agent.Topology.{Ref, Reference}
  alias Jido.Error.ValidationError

  defmodule Unresolved do
    def __agent_config__, do: raise("Authoring must not resolve member sources")
  end

  defmodule Label do
    defstruct [:key, :value, :__spark_metadata__]
  end

  defmodule Labels do
    @label %Spark.Dsl.Entity{
      name: :label,
      target: Label,
      args: [:key, :value],
      schema: [key: [type: :atom, required: true], value: [type: :any, required: true]]
    }

    use Spark.Dsl.Extension,
      dsl_patches: [
        %Spark.Dsl.Patch.AddEntity{section_path: [:topology, :agents], entity: @label}
      ]

    def lower_topology(config, labels) do
      metadata = Map.new(labels, &{&1.key, &1.value})
      {:ok, Map.put(config, :metadata, metadata), []}
    end
  end

  defmodule Worker do
    use Jido.Agent, name: "worker"

    agent do
      schema Zoi.object(%{count: Zoi.integer() |> Zoi.default(0)})
    end

    routes do
      route "counter.add", JidoTest.AgentContract.Add
    end
  end

  defmodule Included do
    use Jido.Agent, name: "included"

    agent do
      schema Zoi.object(%{label: Zoi.string()})
    end

    topology do
      agents do
        agent :worker, Worker
      end

      imports do
        bus :events
      end

      exports do
        agent :public_worker, from: :worker
      end
    end
  end

  defmodule Team do
    use Jido.Agent, name: "team"

    agent do
      schema Zoi.object(%{
               count: Zoi.integer() |> Zoi.default(0),
               workers: Zoi.integer() |> Zoi.default(2),
               accounts: Zoi.list(Zoi.map()) |> Zoi.default([]),
               label: Zoi.string() |> Zoi.default("team")
             })

      metadata %{domain: true}
    end

    routes do
      route "counter.add", JidoTest.AgentContract.Add
    end

    topology do
      metadata %{composition: true}

      agents do
        agent :coordinator, Worker

        agent :neutral,
          definition: Worker.definition(),
          node: :worker@example,
          activation: :lazy

        group :workers, Worker,
          count: state(:workers),
          initial_state: %{count: member(:index)},
          activation: :lazy,
          depends_on: [:events]

        group :accounts, Worker, members: state(:accounts), key_by: :account_id
        group :empty, Worker, count: 0
      end

      resources do
        bus :events, config: [max_log_size: 100]
        bus :audit
      end

      relationships do
        owns :coordinator, :workers, on_parent_exit: :continue
      end

      connections do
        subscribe :workers, to: :events, path: "counter.*", delivery: :broadcast
      end

      topologies do
        include :team, Included.definition().topology do
          inputs %{label: state(:label)}
          bind :events, to: :events
        end
      end

      imports do
        bus :external
      end

      exports do
        agent :coordinator, from: :coordinator
        agent :nested, from: ref(:team, :public_worker)
        group :workers, from: :workers
        bus :events, from: :events
      end

      children([
        %{
          key: :child,
          module: Included,
          initial_state: %{label: state(:label)},
          activation: :lazy,
          gate: %{
            commands: [%{type: "counter.add", member: root()}],
            events: ["counter.changed"],
            to: :events
          }
        }
      ])

      startup do
        concurrency 4
        max_agents 100
        retry_interval 500
        task_timeout 2_000
      end
    end
  end

  @tag obligation: ["jido.agent.I1", "jido.agent.I2", "jido.agent.I25"]
  test "a plain Agent has no composition wrapper or topology value" do
    definition = Worker.definition()
    assert definition.topology == nil
    assert Agent.define!(name: "plain").topology == nil
    assert Agent.define!(name: "plain", topology: nil).topology == nil
    assert Worker.instantiate!().topology == nil
    refute function_exported?(Worker, :__topology_config__, 0)
    refute function_exported?(Team, :topology, 0)
  end

  @tag obligation: "jido.agent.I22"
  test "one Agent holds the existing topology map shape and all declaration sections" do
    topology = Team.definition().topology

    assert is_map(topology) and not is_struct(topology)

    assert Enum.sort(Map.keys(topology)) ==
             Enum.sort([
               :metadata,
               :agents,
               :groups,
               :resources,
               :relationships,
               :connections,
               :includes,
               :children,
               :imports,
               :exports,
               :startup
             ])

    assert [
             %{key: :coordinator, module: Worker, activation: :eager},
             %{key: :neutral, definition: neutral, node: :worker@example, activation: :lazy}
           ] = topology.agents

    assert neutral === Worker.definition()

    assert [
             %{key: :workers, count: count, initial_state: %{count: index}, activation: :lazy},
             %{key: :accounts, members: accounts, key_by: :account_id, activation: :eager},
             %{key: :empty, count: 0}
           ] = topology.groups

    assert count == Reference.state(:workers)
    assert index == Reference.member(:index)
    assert accounts == Reference.state(:accounts)
    refute Map.has_key?(Enum.at(topology.groups, 1), :count)

    assert topology.resources == [
             %{key: :events, kind: :bus, config: [max_log_size: 100]},
             %{key: :audit, kind: :bus, config: []}
           ]

    assert topology.relationships == [
             %{parent: :coordinator, child: :workers, on_parent_exit: :continue}
           ]

    assert topology.connections == [
             %{agent: :workers, to: :events, path: "counter.*", delivery: :broadcast}
           ]

    assert [
             %{
               key: :team,
               topology: included,
               inputs: %{label: %Reference{kind: :state, key: :label}},
               bindings: [%{key: :events, to: :events}]
             }
           ] =
             topology.includes

    assert included === Included.definition().topology

    assert topology.imports == [%{key: :external, kind: :bus}]
    assert Enum.at(topology.exports, 1).from == Ref.ref(:team, :public_worker)

    assert [
             %{
               key: :child,
               module: Included,
               activation: :lazy,
               gate: %{commands: [%{type: "counter.add"}]}
             }
           ] = topology.children

    assert topology.startup == %{
             concurrency: 4,
             max_agents: 100,
             retry_interval: 500,
             task_timeout: 2_000
           }
  end

  @tag obligation: ["jido.agent.I1", "jido.agent.I2", "jido.agent.I25"]
  test "map, keyword, and DSL authoring have one canonical Agent value" do
    definition = Team.definition()
    fields = Map.from_struct(definition)
    assert Agent.define!(fields) === definition
    assert Agent.define!(Enum.to_list(fields)) === definition

    instance = Team.instantiate!(id: "team")
    assert Agent.definition(instance) === definition
    assert instance.topology === definition.topology
    assert instance.state == %{count: 0, workers: 2, accounts: [], label: "team"}
    assert definition.metadata == %{domain: true}
    assert definition.topology.metadata == %{composition: true}
    refute Map.has_key?(definition.topology, :schema)
    assert {:error, %ValidationError{}} = Team.instantiate(topology: %{})
    assert {:error, %ValidationError{}} = Team.instantiate(input: %{workers: 0})
  end

  @tag obligation: "jido.agent.I1"
  test "commands and checkpoint restore retain topology as definition data" do
    definition =
      Agent.define!(
        Map.from_struct(Team.definition())
        |> Map.put(:module, Agent)
        |> Map.put(:vsn, nil)
      )

    instance = Agent.instantiate!(definition, id: "team")
    signal = Jido.Signal.new!("counter.add", %{amount: 1}, source: "/test")

    assert {:ok, next, []} = Agent.cmd(instance, signal)
    assert next.topology === instance.topology
    assert next.state.count == 1
    assert {:ok, checkpoint} = Agent.checkpoint(next)
    assert {:ok, ^next} = Agent.restore(Agent, checkpoint)
  end

  @tag obligation: "jido.agent.I20"
  test "the old Agent document format rejects composition instead of dropping it" do
    for agent <- [Team.definition(), Team.instantiate!()] do
      assert {:error, %ValidationError{}} = Agent.Codec.encode(agent)
      assert {:error, %ValidationError{}} = Agent.Codec.encode(agent, %{})
    end

    assert {:ok, %{"version" => 2}, _registry} = Agent.Codec.encode(Worker.definition())
  end

  @tag obligation: "jido.agent.I3"
  test "invalid topology shape has a structured error at the Agent boundary" do
    for topology <- [
          false,
          [],
          %URI{},
          %{unknown: true},
          %{agents: %{}},
          %{groups: [1]},
          %{agents: [%{key: :worker, module: Worker, activation: :invalid}]},
          %{groups: [%{key: :workers, module: Worker, activation: :invalid}]},
          %{resources: [%{key: :events, other: true}]},
          %{startup: %{concurrency: 0}},
          %{metadata: %{pid: self()}},
          %{schema: Zoi.integer()},
          %{name: self()}
        ] do
      assert {:error, %ValidationError{details: %{source_path: [:topology | _]}}} =
               Agent.define(name: "invalid", topology: topology)
    end
  end

  @tag obligation: ["jido.agent.I1", "jido.agent.I22"]
  test "declarations preserve exact values and defer source binding" do
    topology = %{
      agents: [
        %{key: :worker, module: Unresolved, initial_state: %{enabled: false, count: 0, note: nil}}
      ],
      groups: [
        %{key: :counted, module: Unresolved},
        %{key: :keyed, module: Unresolved, members: [], key_by: :id}
      ]
    }

    definition = Agent.define!(name: "unresolved", topology: topology)
    assert [%{initial_state: %{enabled: false, count: 0, note: nil}}] = definition.topology.agents
    assert [%{count: 1}, keyed] = definition.topology.groups
    assert keyed.members == []
    refute Map.has_key?(keyed, :count)
    assert Agent.instantiate!(definition).topology === definition.topology
  end

  @tag obligation: "jido.agent.I22"
  test "an empty block is an empty topology map and reference helpers stay in their section" do
    JidoTest.AgentContract.with_agent(
      """
      topology do
      end
      def input(value), do: {:application, value}
      """,
      fn module ->
        assert is_map(module.definition().topology)
        assert module.definition().topology.agents == []
        refute Map.has_key?(module.definition().topology, :schema)
        assert module.input(:own) == {:application, :own}
      end
    )
  end

  @tag obligation: ["jido.agent.I2", "jido.agent.I22"]
  test "state sources and lazy startup stay declarations when an Agent value is constructed" do
    definition = Team.definition()

    instance =
      Team.instantiate!(state: %{workers: 5, accounts: [%{account_id: "a"}], label: "custom"})

    assert instance.state.workers == 5
    assert instance.topology === definition.topology
    assert Enum.at(instance.topology.groups, 0).count === Reference.state(:workers)
    assert Enum.at(instance.topology.groups, 1).members === Reference.state(:accounts)
    assert Enum.at(instance.topology.agents, 1).definition === Worker.definition()
    assert Enum.at(instance.topology.agents, 1).activation == :lazy
    refute Map.has_key?(instance, :input)
  end

  @tag obligation: "jido.agent.I22"
  test "fixed definition configuration needs no composition input schema" do
    JidoTest.AgentContract.with_agent(
      """
      @worker_count 3
      topology do
        agents do
          group :workers, JidoTest.Contract.AgentTopologyTest.Worker,
            count: @worker_count,
            activation: :lazy
        end
      end
      def state(value), do: {:application, value}
      """,
      fn module ->
        assert [%{key: :workers, count: 3, activation: :lazy}] =
                 module.definition().topology.groups

        refute Map.has_key?(module.definition().topology, :schema)
        assert module.state(:own) == {:application, :own}
      end
    )

    refute Map.has_key?(Agent.define!(name: "empty", topology: %{}).topology, :schema)
  end

  @tag obligation: "jido.agent.I22"
  test "an explicit composition input schema stays separate from the Agent domain schema" do
    JidoTest.AgentContract.with_agent(
      """
      agent do
        schema Zoi.object(%{count: Zoi.integer() |> Zoi.default(0)})
      end
      topology do
        schema Zoi.object(%{workers: Zoi.integer()})
        agents do
          group :workers, JidoTest.Contract.AgentTopologyTest.Worker, count: input(:workers)
        end
      end
      """,
      fn module ->
        definition = module.definition()
        assert definition.schema.fields[:count]
        assert definition.topology.schema.fields[:workers]
        assert [%{count: %Reference{kind: :input, key: :workers}}] = definition.topology.groups
        assert module.instantiate!().state == %{count: 0}
      end
    )
  end

  @tag obligation: "jido.agent.I3"
  test "worker startup policy is checked in the DSL" do
    for entry <- ["agent :worker", "group :workers"] do
      assert_raise Spark.Error.DslError, ~r/activation/, fn ->
        JidoTest.AgentContract.with_agent(
          """
          topology do
            agents do
              #{entry}, JidoTest.Contract.AgentTopologyTest.Worker, activation: :invalid
            end
          end
          """,
          fn _module -> flunk("Invalid startup policy compiled") end
        )
      end
    end
  end

  @tag obligation: "jido.agent.I22"
  test "topology extension declarations lower through the shared static authoring boundary" do
    JidoTest.AgentContract.with_agent(
      """
      topology do
        agents do
          label :team, "example"
        end
      end
      """,
      fn module ->
        assert module.definition().topology.metadata == %{team: "example"}
        assert module.definition().metadata == %{}
      end,
      ", extensions: [JidoTest.Contract.AgentTopologyTest.Labels]"
    )
  end
end

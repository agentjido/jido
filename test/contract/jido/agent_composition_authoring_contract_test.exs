defmodule JidoTest.Contract.AgentCompositionAuthoringTest do
  use Covenant.Case, component: "jido.agent", async: true

  alias __MODULE__.Worker
  alias Jido.Agent
  alias Jido.Agent.Topology.Reference
  alias Jido.Error.ValidationError
  alias Jido.Plugin.Scheduler

  defmodule Worker do
    use Jido.Agent, name: "shape_worker"
  end

  defmodule Nested do
    use Jido.Agent, name: "shape_nested"

    topology do
      agents do
        agent :leaf, JidoTest.Contract.AgentCompositionAuthoringTest.Worker
      end
    end
  end

  defmodule Timed do
    use Jido.Agent, name: "timed"

    agent do
      plugin Jido.Plugin.Scheduler
    end

    schedules do
      schedule :refresh,
        every: 60_000,
        signal: %{type: "team.refresh", data: %{enabled: false, count: 0, note: nil}}

      schedule :report, cron: "0 9 * * *", signal: %{type: "team.report"}

      schedule :durable,
        cron: "*/5 * * * *",
        timezone: "Etc/UTC",
        delivery: :durable,
        generation: 1,
        signal: %{type: "team.work"}
    end
  end

  defmodule Composed do
    use Jido.Agent, name: "composed"

    alias Jido.Agent.Ref

    topology do
      agents do
        agent :leader, JidoTest.Contract.AgentCompositionAuthoringTest.Worker

        agent :service, JidoTest.Contract.AgentCompositionAuthoringTest.Worker,
          placement: :independent,
          activation: :deferred

        group :workers, JidoTest.Contract.AgentCompositionAuthoringTest.Worker,
          count: 2,
          placement: :owned,
          activation: :lazy
      end

      resources do
        bus :events
      end

      relationships do
        owns root(), :leader
        owns :leader, :workers, on_parent_exit: :continue
      end

      connections do
        subscribe root(), to: :events, path: "worker.completed"
        subscribe :workers, to: :events, path: "work.all", delivery: :broadcast
        subscribe :workers, to: :events, path: "work.one", delivery: :one
      end

      imports do
        agent :billing,
          ref: Ref.new!(namespace: "local", partition: "tenant", id: "billing")
      end

      exports do
        agent :team, from: root()
      end

      children([
        %{
          key: :nested,
          module: JidoTest.Contract.AgentCompositionAuthoringTest.Nested,
          activation: :lazy
        }
      ])
    end
  end

  @tag obligation: ["jido.agent.I26", "jido.agent.I28"]
  test "root endpoints refer to the enclosing Agent without adding a coordinator" do
    definition = Composed.definition()
    topology = definition.topology
    assert [%{key: :leader}, %{key: :service}] = topology.agents
    assert Enum.at(topology.relationships, 0).parent == Reference.root()
    assert Enum.at(topology.connections, 0).agent == Reference.root()
    assert [%{key: :team, from: root}] = topology.exports
    assert root == Reference.root()
    assert Agent.instantiate!(definition).topology === topology
    refute function_exported?(Composed, :instantiate_topology, 1)
    refute function_exported?(Composed, :activate_topology, 1)
  end

  @tag obligation: ["jido.agent.I27", "jido.agent.I29"]
  test "startup policy, containment, and logical parent policy are independent data" do
    topology = Composed.definition().topology

    assert [
             %{activation: :eager, placement: :owned},
             %{activation: :deferred, placement: :independent}
           ] = topology.agents

    assert [%{activation: :lazy, placement: :owned}] = topology.groups

    assert Enum.at(topology.relationships, 1) == %{
             parent: :leader,
             child: :workers,
             on_parent_exit: :continue
           }

    assert [
             %{
               module: JidoTest.Contract.AgentCompositionAuthoringTest.Nested,
               activation: :lazy,
               placement: :owned
             }
           ] = topology.children

    refute Map.has_key?(hd(topology.children), :director)
    refute Map.has_key?(hd(topology.children), :input)
  end

  @tag obligation: "jido.agent.I29"
  test "imported Agent endpoints retain stable Refs without creating or adopting Agents" do
    assert [%{key: :billing, kind: :agent, ref: ref}] = Composed.definition().topology.imports
    assert ref === Agent.Ref.new!(namespace: "local", partition: "tenant", id: "billing")
    assert length(Composed.definition().topology.agents) == 2

    for ref <- [
          self(),
          "billing",
          %{id: "billing"},
          %Agent.Ref{namespace: "", partition: nil, id: "billing"}
        ] do
      assert_invalid(%{imports: [%{key: :billing, kind: :agent, ref: ref}]})
    end

    assert_invalid(%{imports: [%{key: :events, kind: :bus, ref: ref}]})
  end

  @tag obligation: "jido.agent.I30"
  test "group delivery modes are explicit and preserve one versus broadcast" do
    assert Enum.map(Composed.definition().topology.connections, &Map.get(&1, :delivery)) == [
             nil,
             :broadcast,
             :one
           ]

    base = %{groups: [%{key: :workers, module: Worker, count: 0}]}

    for delivery <- [:missing, :random, nil] do
      connection = %{agent: :workers, to: :events, path: "work"}

      connection =
        if delivery == :missing, do: connection, else: Map.put(connection, :delivery, delivery)

      assert_invalid(Map.put(base, :connections, [connection]))
    end

    assert_invalid(%{
      connections: [%{agent: Reference.root(), to: :events, path: "work", delivery: :broadcast}]
    })
  end

  @tag obligation: "jido.agent.I27"
  test "all child collections require exactly one Agent source" do
    for collection <- [:agents, :groups, :children],
        fields <- [
          %{},
          %{module: nil},
          %{module: true},
          %{module: "worker"},
          %{definition: %{}},
          %{definition: Worker.instantiate!()},
          %{module: Worker, definition: Worker.definition()},
          %{topology: %{}, director: Worker}
        ] do
      assert_invalid(%{collection => [Map.put(fields, :key, :worker)]})
    end

    for collection <- [:agents, :groups, :children] do
      definition =
        Agent.define!(
          name: "source",
          topology: %{collection => [%{key: :worker, definition: Worker.definition()}]}
        )

      assert hd(definition.topology[collection]).definition === Worker.definition()
    end
  end

  @tag obligation: ["jido.agent.I27", "jido.agent.I28", "jido.agent.I29"]
  test "composition rejects invalid containment, startup, and gate declarations" do
    for collection <- [:agents, :groups, :children],
        options <- [
          %{placement: :shared},
          %{activation: :invalid},
          %{initial_state: nil},
          %{depends_on: :events},
          %{depends_on: [Reference.state(:events)]}
        ] do
      assert_invalid(%{collection => [Map.merge(%{key: :worker, module: Worker}, options)]})
    end

    for options <- [
          %{max_restarts: -1},
          %{max_seconds: 0},
          %{gate: %{commands: [%{type: "", member: Reference.root()}]}},
          %{gate: %{commands: [%{type: "work.*", member: Reference.root()}]}},
          %{gate: %{commands: [%{type: "work", member: self()}]}},
          %{gate: %{events: ["work.completed"]}},
          %{gate: %{events: [""]}},
          %{gate: %{to: Reference.state(:events)}}
        ] do
      assert_invalid(%{children: [Map.merge(%{key: :worker, module: Worker}, options)]})
    end

    assert_invalid(%{relationships: [%{parent: Reference.root(), child: Reference.root()}]})
  end

  @tag obligation: "jido.agent.I30"
  test "fixed groups reject conflicting membership, unstable keys, and duplicate declarations" do
    for fields <- [
          %{count: -1},
          %{count: 1.0},
          %{count: nil},
          %{count: true},
          %{count: 2, members: [], key_by: :id},
          %{key_by: :id},
          %{members: []},
          %{members: %{a: 1}, key_by: :id},
          %{members: [%{id: "a"}, %{id: "a"}], key_by: :id},
          %{members: [%{}], key_by: :id},
          %{members: [1], key_by: :id}
        ] do
      assert_invalid(%{groups: [Map.merge(%{key: :workers, module: Worker}, fields)]})
    end

    assert_invalid(%{
      agents: [%{key: :same, module: Worker}],
      groups: [%{key: "same", module: Worker}]
    })

    assert_invalid(%{resources: [%{key: :events}, %{key: "events"}]})

    assert_invalid(%{
      exports: [
        %{key: :same, kind: :agent, from: Reference.root()},
        %{key: "same", kind: :agent, from: Reference.root()}
      ]
    })

    definition =
      Agent.define!(
        name: "keyed",
        topology: %{
          groups: [
            %{key: :workers, module: Worker, members: [%{id: "b"}, %{id: "a"}], key_by: :id}
          ]
        }
      )

    assert hd(definition.topology.groups).members == [%{id: "b"}, %{id: "a"}]
    refute Map.has_key?(hd(definition.topology.groups), :count)
  end

  @tag obligation: "jido.agent.I31"
  test "static includes require explicit composition data and preserve parameter mappings" do
    fragment = %{
      agents: [%{key: :worker, module: Worker, initial_state: %{count: Reference.input(:start)}}]
    }

    definition =
      Agent.define!(
        name: "include",
        topology: %{
          includes: [
            %{key: :shared, topology: fragment, inputs: %{start: Reference.state(:count)}}
          ]
        }
      )

    assert [%{topology: %{agents: [%{initial_state: %{count: input}}]}, inputs: %{start: state}}] =
             definition.topology.includes

    assert input == Reference.input(:start)
    assert state == Reference.state(:count)

    for source <- [Worker, Worker.definition(), Worker.instantiate!()] do
      assert_invalid(%{includes: [%{key: :worker, topology: source}]})
    end

    assert_invalid(%{includes: [%{key: :worker, topology: %{agents: [%{key: :bad}]}}]})
  end

  @tag obligation: "jido.agent.I28"
  test "root and value reference helpers stay scoped to topology blocks" do
    JidoTest.AgentContract.with_agent(
      """
      topology do
        exports do
          agent :self, from: root()
        end
      end
      def root(), do: :application_root
      """,
      fn module ->
        assert hd(module.definition().topology.exports).from == Reference.root()
        assert module.root() == :application_root
      end
    )

    for endpoint <- [%Reference{kind: :root, key: :wrong}, Reference.state(:workers), false, ""] do
      assert_invalid(%{exports: [%{key: :root, kind: :agent, from: endpoint}]})
    end
  end

  @tag obligation: ["jido.agent.I32", "jido.agent.I33"]
  test "schedule DSL and data forms produce equal inert Agent definitions" do
    definition = Timed.definition()
    assert definition.topology == nil

    assert definition.schedules == [
             %{
               key: :refresh,
               every: 60_000,
               signal: %{type: "team.refresh", data: %{enabled: false, count: 0, note: nil}},
               delivery: :best_effort,
               missed: :skip
             },
             %{
               key: :report,
               cron: "0 9 * * *",
               timezone: "Etc/UTC",
               signal: %{type: "team.report", data: %{}},
               delivery: :best_effort,
               missed: :skip
             },
             %{
               key: :durable,
               cron: "*/5 * * * *",
               timezone: "Etc/UTC",
               signal: %{type: "team.work", data: %{}},
               delivery: :durable,
               generation: 1,
               missed: :skip
             }
           ]

    assert Agent.define!(Map.from_struct(definition)) === definition
    assert Agent.define!(Map.from_struct(definition) |> Enum.to_list()) === definition

    first = Timed.instantiate!()
    second = Timed.instantiate!()
    assert first.id != second.id
    assert first.schedules === definition.schedules
    assert second.schedules === definition.schedules
    assert first.state.scheduler == %{cron: %{}}
    assert second.state.scheduler == %{cron: %{}}
    refute Map.has_key?(hd(first.schedules).signal, :id)
    refute Map.has_key?(hd(first.schedules).signal, :time)
    assert {:error, %ValidationError{}} = Timed.instantiate(schedules: [])
  end

  @tag obligation: "jido.agent.I32"
  test "schedule declarations require the Scheduler Plugin and retain declaration order" do
    schedule = %{key: :tick, every: 1_000, signal: %{type: "tick"}}

    for plugins <- [[], [JidoTest.AgentContract.Stateless]] do
      assert {:error, %ValidationError{details: %{source_path: [:schedules]}}} =
               Agent.define(name: "missing", plugins: plugins, schedules: [schedule])
    end

    assert_raise CompileError, ~r/Scheduler/, fn ->
      JidoTest.AgentContract.with_agent(
        """
        schedules do
          schedule :tick, every: 1000, signal: %{type: "tick"}
        end
        """,
        fn _ -> flunk("missing Plugin compiled") end
      )
    end

    assert Agent.define!(name: "plain").schedules == []
  end

  @tag obligation: "jido.agent.I33"
  test "invalid schedules fail at a structured authoring boundary" do
    base = %{key: :tick, every: 1_000, signal: %{type: "tick"}}

    for schedule <- [
          Map.delete(base, :every),
          Map.put(base, :cron, "* * * * *"),
          %{base | every: 0},
          %{base | every: -1},
          %{base | every: nil},
          %{base | every: 4_294_967_296},
          %{base | key: ""},
          %{base | key: false},
          Map.put(base, :timezone, "Etc/UTC"),
          %{base | signal: %{type: ""}},
          %{base | signal: %{}},
          %{base | signal: %{type: "tick", id: "fixed"}},
          %{base | signal: %{type: "tick", data: self()}},
          Map.put(base, :to, Reference.root()),
          Map.put(base, :missed, :all),
          Map.put(base, :delivery, :durable),
          Map.put(base, :generation, 2_147_483_648),
          %{key: :tick, cron: "bad cron", signal: %{type: "tick"}},
          %{key: :tick, cron: "* * * * *", timezone: "Invalid/Zone", signal: %{type: "tick"}}
        ] do
      assert {:error, %ValidationError{details: %{source_path: [:schedules | _]}}} =
               Agent.define(name: "invalid", plugins: [Scheduler], schedules: [schedule])
    end

    for schedules <- [nil, %{}, [base | :tail], [base, %{base | key: "tick"}]] do
      assert {:error, %ValidationError{}} =
               Agent.define(name: "invalid", plugins: [Scheduler], schedules: schedules)
    end
  end

  @tag obligation: "jido.agent.I33"
  test "DSL schedule conflicts and invalid explicit values are rejected" do
    for {options, error} <- [
          {"every: 0", Spark.Error.DslError},
          {"every: nil", Spark.Error.DslError},
          {"every: 1000, cron: \"* * * * *\"", CompileError},
          {"cron: \"bad cron\"", CompileError},
          {"delivery: :durable, every: 1000", CompileError}
        ] do
      assert_raise error, fn ->
        JidoTest.AgentContract.with_agent(
          """
          agent do
            plugin Jido.Plugin.Scheduler
          end
          schedules do
            schedule :tick, #{options}, signal: %{type: "tick"}
          end
          """,
          fn _ -> flunk("Invalid schedule compiled") end
        )
      end
    end
  end

  @tag obligation: "jido.agent.I34"
  test "the existing document format rejects new authoring data without loss" do
    for agent <- [Timed.definition(), Timed.instantiate!(), Composed.definition()] do
      assert {:error, %ValidationError{}} = Agent.Codec.encode(agent)
      assert {:error, %ValidationError{}} = Agent.Codec.encode(agent, %{})
    end
  end

  defp assert_invalid(topology) do
    assert {:error, %ValidationError{details: %{source_path: [:topology | _]}}} =
             Agent.define(name: "invalid", topology: topology)
  end
end

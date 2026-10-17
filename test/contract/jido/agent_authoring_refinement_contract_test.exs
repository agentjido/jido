defmodule JidoTest.Contract.AgentAuthoringRefinementTest do
  use Covenant.Case, component: "jido.agent", async: false

  alias Jido.Agent
  alias Jido.Agent.Topology.{Ref, Reference}
  alias Jido.Error.ValidationError
  alias Jido.Plugin.Scheduler
  alias JidoTest.AgentContract, as: F

  setup do
    previous = Code.compiler_options(debug_info: true)
    on_exit(fn -> Code.compiler_options(previous) end)
    :ok
  end

  defmodule LowerComposition do
    use Spark.Dsl.Extension

    def lower_agent(%{topology: %{groups: [group]} = topology} = config, entities) do
      count = if config.metadata[:invalid], do: -1, else: 0
      {:ok, %{config | topology: %{topology | groups: [%{group | count: count}]}}, entities}
    end
  end

  @tag obligation: ["jido.agent.I1", "jido.agent.I5", "jido.agent.I27"]
  test "DSL decoding preserves literal markers, false, nil, zero, and fixed Bus kind" do
    F.with_agent(
      """
      topology do
        agents do
          agent :worker, Example.Worker,
            node: {:present, :literal},
            initial_state: %{flag: false, note: nil, value: {:present, 0}}
          agent :other, Example.Worker, node: nil
          group :workers, Example.Worker, count: 0
        end
        resources do
          bus :events, config: {:present, %{flag: false, note: nil, count: 0}}
        end
      end
      """,
      fn module ->
        topology = module.definition().topology

        expected = %{
          agents: [
            %{
              key: :worker,
              module: Example.Worker,
              node: {:present, :literal},
              initial_state: %{flag: false, note: nil, value: {:present, 0}}
            },
            %{key: :other, module: Example.Worker, node: nil}
          ],
          groups: [%{key: :workers, module: Example.Worker, count: 0}],
          resources: [%{key: :events, config: {:present, %{flag: false, note: nil, count: 0}}}]
        }

        assert topology === Agent.define!(%{name: "same", topology: expected}).topology
        assert topology === Agent.define!(name: "same", topology: expected).topology
      end
    )
  end

  @tag obligation: ["jido.agent.I1", "jido.agent.I3", "jido.agent.I33"]
  test "marker-shaped required and defaulted values cannot bypass validation" do
    assert {:error, %ValidationError{}} =
             Agent.define(
               name: "bad",
               topology: %{
                 agents: [
                   %{key: :worker, module: Example.Worker, initial_state: {:present, %{count: 1}}}
                 ]
               }
             )

    for body <- [
          "topology do\n agents do\n agent :worker, Example.Worker, initial_state: {:present, %{count: 1}}\n end\nend",
          "agent do\n plugin Jido.Plugin.Scheduler\nend\nschedules do\n schedule {:present, :tick}, every: 1000, signal: %{type: \"tick\"}\nend"
        ] do
      assert_raise CompileError, fn ->
        F.with_agent(body, fn _ -> flunk("invalid value compiled") end)
      end
    end
  end

  @tag obligation: ["jido.agent.I1", "jido.agent.I27", "jido.agent.I31"]
  test "all child sources retain the normalized neutral definition, including inside includes" do
    raw = %{Agent.define!(name: "child") | plugins: [Scheduler]}
    canonical = Agent.define!(raw)

    for collection <- [:agents, :groups, :children] do
      fragment = %{collection => [%{key: :worker, definition: raw}]}

      outer =
        Agent.define!(
          name: "outer",
          topology:
            Map.put(fragment, :includes, [
              %{key: :nested, topology: fragment}
            ])
        )

      assert hd(outer.topology[collection]).definition === canonical
      assert hd(hd(outer.topology.includes).topology[collection]).definition === canonical
      assert Agent.define!(outer) === outer
    end
  end

  @tag obligation: ["jido.agent.I28", "jido.agent.I30", "jido.agent.I31"]
  test "included group exports require and retain delivery, while Agent exports reject it" do
    fragment = %{
      groups: [%{key: :workers, module: Example.Worker}],
      agents: [%{key: :leader, module: Example.Worker}],
      exports: [
        %{key: :pool, kind: :group, from: :workers},
        %{key: :one, kind: :agent, from: :leader}
      ]
    }

    topology = %{includes: [%{key: :team, topology: fragment}], connections: []}

    for delivery <- [:one, :broadcast] do
      connection = %{agent: Ref.ref(:team, :pool), to: :events, path: "work", delivery: delivery}
      definition = Agent.define!(name: "team", topology: %{topology | connections: [connection]})
      assert definition.topology.connections === [connection]
    end

    for connection <- [
          %{agent: Ref.ref(:team, :pool), to: :events, path: "work"},
          %{agent: Ref.ref(:team, :one), to: :events, path: "work", delivery: :broadcast}
        ] do
      assert {:error, %ValidationError{}} =
               Agent.define(name: "bad", topology: %{topology | connections: [connection]})
    end

    F.with_agent(
      """
      topology do
        topologies do
          include :team, %{groups: [%{key: :workers, module: Example.Worker}],
            exports: [%{key: :pool, kind: :group, from: :workers}]}
        end
        connections do
          subscribe ref(:team, :pool), to: :events, path: "work", delivery: :one
        end
      end
      """,
      fn module -> assert [%{delivery: :one}] = module.definition().topology.connections end
    )
  end

  @tag obligation: ["jido.agent.I28", "jido.agent.I30"]
  test "unresolved export kinds remain binding intent with valid delivery shape" do
    connection = %{
      agent: Ref.ref(:external, :pool),
      to: :events,
      path: "work",
      delivery: :broadcast
    }

    assert Agent.define!(name: "deferred", topology: %{connections: [connection]}).topology.connections ==
             [connection]

    assert {:error, %ValidationError{}} =
             Agent.define(
               name: "bad",
               topology: %{connections: [%{connection | delivery: :random}]}
             )
  end

  @tag obligation: ["jido.agent.I28", "jido.agent.I30", "jido.agent.I33"]
  test "keys have one nonempty UTF-8 byte bound in declarations, schedules, and references" do
    invalid = [
      nil,
      true,
      false,
      :"",
      "",
      String.duplicate("a", 256),
      String.to_atom(String.duplicate("界", 100)),
      <<255>>
    ]

    for key <- invalid do
      assert {:error, %ValidationError{}} =
               Agent.define(name: "bad", topology: %{resources: [%{key: key}]})

      assert {:error, %ValidationError{}} =
               Agent.define(
                 name: "bad",
                 plugins: [Scheduler],
                 schedules: [
                   %{key: key, every: 1000, signal: %{type: "tick"}}
                 ]
               )

      assert_raise ArgumentError, fn -> Reference.state(key) end
      assert_raise ArgumentError, fn -> Ref.ref(:team, key) end
    end

    for key <- [:worker, "worker", String.duplicate("a", 255)] do
      assert Reference.state(key).key === key
      assert Ref.ref(:team, key).key === to_string(key)

      assert Agent.define!(name: "valid", topology: %{resources: [%{key: key}]}).topology.resources
             |> hd()
             |> Map.fetch!(:key) === key
    end
  end

  @tag obligation: ["jido.agent.I28", "jido.agent.I29"]
  test "self ownership uses the same key identity for all endpoint forms" do
    for {parent, child} <- [
          {:worker, "worker"},
          {{:child, :worker}, "worker"},
          {{:group, :workers, :first}, {:group, "workers", "first"}},
          {%Ref{component: :team, key: :worker}, Ref.ref(:team, :worker)},
          {Reference.root(), Reference.root()}
        ] do
      assert {:error, %ValidationError{}} =
               Agent.define(
                 name: "bad",
                 topology: %{relationships: [%{parent: parent, child: child}]}
               )
    end

    assert {:ok, _} =
             Agent.define(
               name: "valid",
               topology: %{relationships: [%{parent: :parent, child: :child}]}
             )
  end

  @tag obligation: ["jido.agent.I22", "jido.agent.I30"]
  test "Agent extensions lower authored topology before canonical validation and defaults" do
    body = """
    topology do
      agents do
        group :workers, Example.Worker, count: -1
      end
    end
    """

    F.with_agent(
      body,
      fn module ->
        assert [%{count: 0, initial_state: %{}, activation: :eager, placement: :owned}] =
                 module.definition().topology.groups
      end,
      ", extensions: [#{inspect(LowerComposition)}]"
    )

    F.with_agent(
      "topology do\n agents do\n group :workers, Example.Worker\n end\nend",
      fn module ->
        assert [%{count: 1}] = module.definition().topology.groups
      end
    )
  end

  @tag obligation: ["jido.agent.I22", "jido.agent.I35"]
  test "invalid extension output still reaches the final validator at its declaration" do
    assert_error_line(
      """
      agent do
        metadata %{invalid: true}
      end
      topology do
        agents do
          group :workers, Example.Worker, count: 1
        end
      end
      """,
      "group :workers",
      ", extensions: [#{inspect(LowerComposition)}]"
    )
  end

  @tag obligation: "jido.agent.I35"
  test "topology conflicts and schedule conflicts report their own declaration lines" do
    assert_error_line(
      """
      topology do
        agents do
          group :workers, Example.Worker, count: 2, members: [], key_by: :id
        end
      end
      """,
      "group :workers"
    )

    assert_error_line(
      """
      agent do
        plugin Jido.Plugin.Scheduler
      end
      schedules do
        schedule :tick, every: 1000, cron: "* * * * *", signal: %{type: "tick"}
      end
      """,
      "schedule :tick"
    )
  end

  @tag obligation: "jido.agent.I35"
  test "field errors, included maps, and nested bindings retain source locations" do
    for {body, marker} <- [
          {"topology do\n agents do\n agent :worker, Example.Worker do\n initial_state 99\n end\n end\nend",
           "initial_state 99"},
          {"topology do\n topologies do\n include :team, %{includes: [%{key: :nested, topology: %{groups: [%{key: :workers, module: Example.Worker, count: -1}]}}]}\n end\nend",
           "include :team"},
          {"topology do\n topologies do\n include :team, %{} do\n bind :events do\n to {:bad, :endpoint}\n end\n end\n end\nend",
           "to {:bad"},
          {"agent do\n plugin Jido.Plugin.Scheduler\nend\nschedules do\n schedule :tick do\n every 1000\n signal %{type: \"\"}\n end\nend",
           "signal %{type:"}
        ] do
      assert_error_line(body, marker)
    end

    assert {:error, %ValidationError{details: %{source_path: [:schedules, 0, :every]}}} =
             Agent.define(
               name: "bad",
               plugins: [Scheduler],
               schedules: [
                 %{key: :tick, every: nil, signal: %{type: "tick"}}
               ]
             )
  end

  defp assert_error_line(body, marker, options \\ "") do
    module = Module.concat(__MODULE__, "Invalid#{System.unique_integer([:positive])}")

    source =
      "defmodule #{inspect(module)} do\nuse Jido.Agent, name: \"invalid\"#{options}\n#{body}\nend\n"

    expected =
      source
      |> String.split("\n")
      |> Enum.find_index(&String.contains?(&1, marker))
      |> Kernel.+(1)

    error =
      assert_raise CompileError, fn ->
        JidoTest.AuthoringCompiler.with_compiled(
          source,
          fn _ -> flunk("invalid definition compiled") end,
          modules: [module]
        )
      end

    assert error.file == "authoring_fixture.ex"
    assert error.line == expected, "#{inspect(error)}; expected line #{expected}"
  end
end

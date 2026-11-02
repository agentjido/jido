Code.require_file("../support/agents/composable_fixtures.exs", __DIR__)
Code.require_file("../support/agents/composable_compiler.exs", __DIR__)
Code.require_file("../support/agents/team_definitions.exs", __DIR__)
Code.require_file("../support/agents/alice_definitions.exs", __DIR__)

defmodule Jido.AgentExtensionsAuthoringTest do
  use ExUnit.Case, async: true
  @moduletag :authoring
  alias Jido.Agent
  alias Jido.Agent.{Error, Topology}
  alias Jido.Plugin.Scheduler.DSL, as: Scheduling
  alias Jido.Plugin.Bus.DSL, as: SignalBus

  alias JidoTest.ComposableAgent.{
    Action,
    Audit,
    OwnedPlugin,
    PluginFirst,
    PluginLast,
    ScheduleShort,
    ScheduleBlock,
    Team
  }

  alias JidoTest.ComposableAgent.Compiler

  defmodule BehaviorOnly do
    use Jido.Plugin, id: "test.behavior"
  end

  defmodule DuplicateID do
    use Jido.Plugin, id: "test.audit"
  end

  defmodule ConflictingSection do
    @section %Spark.Dsl.Section{name: :audit}
    use Jido.Plugin, id: "test.conflict", sections: [@section]
  end

  defmodule CoreConflict do
    @section %Spark.Dsl.Section{name: :routes}
    use Jido.Plugin, id: "test.core_conflict", sections: [@section]
  end

  defmodule CoreEndpointConflict do
    use Jido.Plugin, id: "test.endpoint_conflict"
    def endpoint_kinds, do: [:agent]
  end

  defp contribution(provider, data),
    do: %{id: provider.id(), provider: provider, vsn: provider.vsn(), data: data}

  defp define(provider, data, routes \\ []) do
    Agent.define(%{name: "extended", routes: routes, plugins: [contribution(provider, data)]})
  end

  defp action(type),
    do: %{
      path: type,
      handler: %{kind: :action, target: Action},
      state: %{source: :output, path: []}
    }

  test "full extension DSL data equals an independently written Map in provider order" do
    expected = [
      contribution(Scheduling, %{
        schedules: [
          %{
            name: :review,
            timing: %{kind: :every, milliseconds: 60_000},
            signal: %{type: "plan.request", data: %{value: "review"}}
          },
          %{
            name: :refresh,
            timing: %{kind: :cron, expression: "*/5 * * * *", timezone: "Etc/UTC"},
            signal: %{type: "work.request", data: %{value: "refresh"}}
          }
        ]
      }),
      contribution(SignalBus, %{buses: [%{name: :events}]})
    ]

    assert Team.definition().plugins === expected

    assert {:ok, from_map} =
             Agent.define(%{
               name: "extended",
               routes: [action("plan.request"), action("work.request")],
               plugins: expected
             })

    assert from_map.plugins === expected
    assert from_map.topology == %{agents: [], connections: []}
  end

  test "short and block schedule DSL lower to the exact same Map" do
    short = ScheduleShort.definition()
    block = ScheduleBlock.definition()
    assert Map.delete(short, :module) === Map.delete(block, :module)

    expected = %{
      schedules: [
        %{
          name: :review,
          timing: %{kind: :every, milliseconds: 60_000},
          signal: %{type: "work.request", data: %{}}
        },
        %{
          name: :refresh,
          timing: %{kind: :cron, expression: "*/5 * * * *", timezone: "Etc/UTC"},
          signal: %{type: "work.request", data: %{value: "refresh"}}
        }
      ]
    }

    assert short.plugins === [contribution(Scheduling, expected)]
    assert {:ok, from_map} = define(Scheduling, expected, [action("work.request")])
    assert from_map.plugins === short.plugins
  end

  test "Plugin declarations do not depend on section order and equal Map provider data" do
    left = PluginFirst.definition()
    right = PluginLast.definition()
    assert Map.delete(left, :module) === Map.delete(right, :module)
    assert left.plugins === [contribution(Audit, %{label: "example", enabled: false})]
    assert {:ok, from_map} = define(Audit, %{label: "example", enabled: false})
    assert from_map.plugins === left.plugins
    refute function_exported?(Audit, :__jido_plugin__, 0)
    assert left.schema === Zoi.object(%{})
    assert left.routes == [] and left.topology == %{agents: [], connections: []}
  end

  test "Plugins use one registration and configuration model" do
    module =
      Compiler.compile(
        "",
        "name: \"generated\", plugins: [{#{inspect(BehaviorOnly)}, %{value: 42}}]"
      )

    assert module.definition().plugins === [contribution(BehaviorOnly, %{value: 42})]
    assert {:ok, from_map} = define(BehaviorOnly, %{value: 42})
    assert from_map.plugins === module.definition().plugins

    module =
      Compiler.compile(
        "audit do label \"example\" end",
        "name: \"extended\",plugins: [JidoTest.ComposableAgent.Audit]"
      )

    assert module.definition().plugins == [
             contribution(Audit, %{label: "example", enabled: true})
           ]
  end

  test "duplicate IDs, providers and section ownership are rejected for Maps and DSL" do
    audit = contribution(Audit, %{label: "test"})

    for entries <- [
          [audit, audit],
          [audit, contribution(DuplicateID, %{})],
          [audit, contribution(ConflictingSection, %{})],
          [contribution(CoreConflict, %{})],
          [contribution(CoreEndpointConflict, %{})]
        ] do
      assert {:error, %Error{}} = Agent.define(%{name: "bad", plugins: entries})
    end

    module =
      Compiler.compile(
        "",
        "name: \"configured\", plugins: [{JidoTest.ComposableAgent.Audit, %{label: \"test\"}}]"
      )

    assert module.definition().plugins == [
             contribution(Audit, %{label: "test", enabled: true})
           ]

    assert_raise Error, fn ->
      Compiler.compile(
        "",
        "name: \"bad\",plugins: [JidoTest.ComposableAgent.Audit,JidoTest.ComposableAgent.Audit]"
      )
    end
  end

  test "provider identity, version, fields and selected provider are checked" do
    entry = contribution(Audit, %{label: "test"})

    for invalid <- [
          %{entry | id: "wrong"},
          %{entry | vsn: 2},
          %{entry | vsn: 1.0},
          %{entry | provider: String},
          Map.put(entry, :state, %{}),
          %{entry | data: %{unknown: true}}
        ] do
      assert {:error, %Error{}} = Agent.define(%{name: "bad", plugins: [invalid]})
    end

    assert {:error, %Error{}} =
             Agent.define(%{name: "bad", plugins: %{Audit => %{label: "old_format"}}})

    diagnostic =
      ExUnit.CaptureIO.capture_io(:stderr, fn ->
        assert_raise CompileError, fn ->
          Compiler.compile("schedules do end")
        end
      end)

    assert diagnostic =~ "undefined function schedules"
  end

  test "schedules validate timing, cron, template and accepted inputs in Map authoring" do
    valid = %{
      name: :review,
      timing: %{kind: :every, milliseconds: 60_000},
      signal: %{type: "work.request", data: %{}}
    }

    for timing <- [
          %{kind: :every, milliseconds: 0},
          %{kind: :every, milliseconds: 3, timezone: "Etc/UTC"},
          %{kind: :every, milliseconds: 3, expression: "* * * * *"},
          %{kind: :cron, expression: "not cron"},
          %{kind: :cron, expression: "* * * * *", timezone: "No/SuchZone"}
        ] do
      assert {:error, %Error{}} =
               define(Scheduling, %{schedules: [%{valid | timing: timing}]}, [
                 action("work.request")
               ])
    end

    assert {:error, %Error{code: :duplicate}} =
             define(Scheduling, %{schedules: [valid, valid]}, [action("work.request")])

    assert {:error, %Error{code: :schedule_input}} = define(Scheduling, %{schedules: [valid]})

    assert {:error, %Error{}} =
             define(Scheduling, %{schedules: [%{valid | signal: %{type: "work.*"}}]}, [
               action("work.request")
             ])

    assert {:error, %Error{}} =
             define(
               Scheduling,
               %{schedules: [%{valid | signal: %{type: "work.request", id: "live"}}]},
               [action("work.request")]
             )

    assert {:ok, definition} =
             define(
               Scheduling,
               %{schedules: [%{valid | timing: %{kind: :cron, expression: "* * * * *"}}]},
               [action("work.request")]
             )

    assert hd(hd(definition.plugins).data.schedules).timing.timezone == "Etc/UTC"
  end

  test "schedule DSL rejects missing or competing timing forms" do
    for block <- [
          "schedule :bad,signal: %{type: \"work.request\"}",
          "schedule :bad,every: 60_000,cron: \"* * * * *\",signal: %{type: \"work.request\"}",
          "schedule :bad,every: 60_000,timezone: \"Etc/UTC\",signal: %{type: \"work.request\"}"
        ] do
      assert_raise Spark.Error.DslError, fn ->
        Compiler.compile(
          "routes do route \"work.request\", JidoTest.ComposableAgent.Action end\nschedules do #{block} end",
          "name: \"bad\",plugins: [Jido.Plugin.Scheduler.DSL]"
        )
      end
    end
  end

  test "bus extension contributes ownership and connection endpoints only" do
    definition = Team.definition()

    expected = [
      %{
        path: "plan.request",
        from: %{kind: :agent, name: :root},
        to: %{kind: :bus, name: :events},
        delivery: :single
      },
      %{
        path: "plan.request",
        from: %{kind: :bus, name: :events},
        to: %{kind: :agent, name: :planner},
        delivery: :single
      },
      %{
        path: "work.request",
        from: %{kind: :agent, name: :root},
        to: %{kind: :bus, name: :events},
        delivery: :single
      },
      %{
        path: "work.request",
        from: %{kind: :agent, name: :planner},
        to: %{kind: :bus, name: :events},
        delivery: :single
      },
      %{
        path: "work.request",
        from: %{kind: :bus, name: :events},
        to: %{kind: :agent, name: :workers},
        delivery: :broadcast
      },
      %{
        path: "work.done",
        from: %{kind: :agent, name: :workers},
        to: %{kind: :agent, name: :root},
        delivery: :single
      }
    ]

    assert definition.topology.connections === expected

    assert definition.topology.agents === [
             %{
               name: :planner,
               definition: JidoTest.ComposableAgent.Worker,
               count: 1,
               initial_state: %{value: %{kind: :state, key: :value}}
             },
             %{
               name: :workers,
               definition: JidoTest.ComposableAgent.Worker,
               count: %{kind: :state, key: :workers},
               initial_state: %{value: %{kind: :state, key: :value}}
             }
           ]

    assert JidoTest.ComposableAgent.Worker.definition().plugins == []
    assert {:ok, empty} = define(SignalBus, %{buses: [%{name: :events}]})
    assert empty.routes == [] and empty.topology == %{agents: [], connections: []}

    assert {:ok, edges} =
             Topology.connections_for(definition, %{kind: :agent, name: :root}, "work.request")

    assert length(edges) == 1
  end

  test "bus wiring rejects missing providers, unknown buses, bus chains and publication broadcast" do
    definition = Team.definition()
    bus = %{kind: :bus, name: :events}
    root = %{kind: :agent, name: :root}

    assert {:error, %Error{code: :unknown_endpoint}} =
             Agent.define(%{
               definition
               | plugins: Enum.reject(definition.plugins, &(&1.provider == SignalBus))
             })

    for edge <- [
          %{
            path: "work.request",
            from: root,
            to: %{kind: :bus, name: :missing},
            delivery: :single
          },
          %{path: "work.request", from: bus, to: bus, delivery: :single},
          %{path: "work.request", from: root, to: bus, delivery: :broadcast}
        ] do
      assert {:error, %Error{}} =
               Agent.define(put_in(definition, [Access.key(:topology), :connections], [edge]))
    end

    for buses <- [[], [%{name: :one}, %{name: :two}], [%{name: "not-an-atom"}]] do
      assert {:error, %Error{}} = define(SignalBus, %{buses: buses})
    end
  end

  test "explicit custom syntax does not depend on section order" do
    definition = JidoTest.ComposableAgent.PluginAlias.definition()
    assert definition.plugins == PluginLast.definition().plugins
    assert hd(definition.routes).handler == %{kind: :action, target: Action}
  end

  test "generated Agents use plugin declarations without source discovery" do
    module =
      Compiler.compile(
        "",
        "name: \"generated_plugin\", plugins: [{JidoTest.ComposableAgent.OwnedPlugin, %{initial: 3}}]"
      )

    assert module.definition().plugins == [contribution(OwnedPlugin, %{initial: 3})]
  end

  test "Team and standalone Alice fixtures validate without handler execution" do
    for module <- [
          JidoTest.ComposableAgent.Definitions.Team,
          JidoTest.ComposableAgent.Definitions.Alice
        ] do
      definition = module.definition()
      assert Agent.define!(definition) === definition
      assert {:ok, ^definition} = Agent.validate(definition)

      assert Enum.all?(
               definition.routes,
               &(&1.handler.kind in [:action, :flow, :transform, :forward])
             )
    end

    alice = JidoTest.ComposableAgent.Definitions.Alice.definition()
    assert alice.topology == %{agents: [], connections: []}
  end

  test "runtime Plugins and Spark extensions use one stored contribution format" do
    alias JidoTest.ComposableAgent.{OwnedPlugin, PluginState}

    expected =
      Agent.define!(%{
        name: "plugin_state",
        module: PluginState,
        schema: Zoi.object(%{value: Zoi.string() |> Zoi.default("domain")}),
        plugins: [contribution(OwnedPlugin, %{initial: 3})]
      })

    assert PluginState.definition() === expected
    assert PluginState.definition() |> Map.from_struct() === expected |> Map.from_struct()
    assert expected.plugins == [contribution(OwnedPlugin, %{initial: 3})]
    refute Map.has_key?(expected, :schedules)
    assert Agent.runtime_plugins(expected) === [{OwnedPlugin, [initial: 3]}]
    assert {:ok, instance} = Agent.instantiate(expected, id: "one")
    assert instance.state === %{value: "domain", owned: 3}
    assert instance.plugins === expected.plugins
    assert Agent.definition(instance) === expected
    assert {:ok, ^instance} = Agent.validate(instance)
    assert {:error, _} = Agent.validate(%{instance | state: %{value: "domain"}})
    assert {:error, _} = Agent.instantiate(expected, id: "bad", state: %{owned: "wrong"})
  end

  test "Plugin schema conflicts fail before instance construction" do
    alias JidoTest.ComposableAgent.{OwnedPlugin, ConflictingPlugin}
    entry = contribution(OwnedPlugin, %{})

    assert {:error, _} =
             Agent.define(%{
               name: "conflict",
               schema: Zoi.object(%{owned: Zoi.string()}),
               plugins: [entry]
             })

    assert {:error, _} =
             Agent.define(%{
               name: "conflict",
               plugins: [entry, contribution(ConflictingPlugin, %{})]
             })
  end
end

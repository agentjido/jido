Code.require_file("../support/agents/composable_fixtures.exs", __DIR__)
Code.require_file("../support/agents/composable_compiler.exs", __DIR__)

defmodule Jido.AgentAuthoringTest do
  use ExUnit.Case, async: true
  @moduletag :authoring
  alias Jido.Agent
  alias Jido.Agent.{Error, Route, Topology}
  alias JidoTest.ComposableAgent.{Action, Flow, Minimal, Named, Team, Worker}
  alias JidoTest.ComposableAgent.Compiler

  defp route(path, handler \\ %{kind: :action, target: Action}, opts \\ []) do
    Map.merge(%{path: path, as: nil, defaults: %{}, handler: handler}, Map.new(opts))
  end

  defp canonical(overrides \\ %{}) do
    struct!(
      Agent,
      Map.merge(
        %{
          id: nil,
          state: nil,
          module: nil,
          name: "test",
          description: nil,
          vsn: 1,
          schema: Zoi.object(%{}),
          metadata: %{},
          signal_source: nil,
          routes: [],
          topology: %{agents: [], connections: []},
          extensions: []
        },
        overrides
      )
    )
  end

  defp agent(name), do: %{kind: :agent, name: name}

  defp edge(path, from, to, delivery \\ :single),
    do: %{path: path, from: agent(from), to: agent(to), delivery: delivery}

  defp composed(topology) do
    Agent.define(%{
      name: "parent",
      schema:
        Zoi.object(%{
          value: Zoi.string() |> Zoi.default("start"),
          workers: Zoi.integer() |> Zoi.default(2)
        }),
      routes: [
        route("work.request"),
        route("work.done", %{kind: :action, target: Action})
      ],
      topology: topology
    })
  end

  defp member(opts \\ %{}),
    do: Map.merge(%{name: :worker, definition: Worker, count: 1, initial_state: %{}}, opts)

  test "minimal DSL lowers to the exact canonical Map, including all defaults" do
    expected = canonical(%{name: "minimal", module: Minimal})
    assert Minimal.definition() === expected
    assert Agent.define!(%{name: "minimal", module: Minimal}) === expected
    assert is_struct(expected, Agent)
    assert Agent.validate(expected) == {:ok, expected}

    assert Minimal.definition() |> Map.from_struct() ===
             Agent.define!(%{name: "minimal", module: Minimal}) |> Map.from_struct()

    assert Zoi.parse(Agent.__schema__(), expected) == {:ok, expected}
    assert Agent.define!(expected) === expected
  end

  test "named Action and Flow DSL lower to the exact independently written Map" do
    expected =
      canonical(%{
        module: Named,
        name: "named",
        description: "Named executables",
        vsn: 3,
        schema: Zoi.object(%{value: Zoi.string() |> Zoi.default("initial")}),
        metadata: %{label: "named"},
        signal_source: "/named",
        routes: [
          route("work.request", %{kind: :action, target: Action},
            as: :work,
            defaults: %{value: "default"}
          ),
          route("plan.request", %{kind: :flow, target: Flow}),
          route("pass.request", %{kind: :action, target: Action}, as: :pass),
          route("work.*", %{kind: :action, target: Action})
        ]
      })

    assert Named.definition() === expected
    assert Agent.define!(expected) === expected
    assert Jido.Instruction.validate(Action) == :ok
    assert Jido.Instruction.validate(Flow) == :ok
    assert {:ok, %{kind: :flow, target: Flow}} = Route.executable(Flow)
  end

  test "inline lowering preserves the exact Map contract around opaque compiled references" do
    definition = Team.definition()
    # Generated executable names are opaque. Only these references come from
    # compilation; every authored and defaulted field below is independent data.
    targets =
      for route <- definition.routes,
          route.handler.kind == :transform,
          into: %{},
          do: {route.path, route.handler.target}

    inline = fn path ->
      Jido.Action.Inline.target!(Team, host: Agent, route: path, role: :action)
    end

    expected_routes = [
      route("work.request", %{kind: :action, target: Action}, as: :request),
      route("plan.request", %{kind: :action, target: Action}, as: :plan),
      route("work.done", %{kind: :action, target: Action}, defaults: %{value: "done"}),
      route("flow.request", %{kind: :flow, target: Flow}),
      route(
        "external.request",
        %{kind: :transform, target: Map.fetch!(targets, "external.request")}
      ),
      route(
        "external.clauses",
        %{kind: :transform, target: Map.fetch!(targets, "external.clauses")}
      ),
      route("inline.request", %{kind: :action, target: inline.("inline.request")}),
      route("inline.emit", %{kind: :action, target: inline.("inline.emit")}),
      route(
        "partial.request",
        %{kind: :transform, target: Map.fetch!(targets, "partial.request")}
      ),
      route("unknown.request", %{kind: :action, target: Action})
    ]

    expected =
      canonical(%{
        module: Team,
        name: "team",
        description: "Test team",
        vsn: 2,
        schema:
          Zoi.object(%{
            value: Zoi.string() |> Zoi.default("input"),
            workers: Zoi.integer() |> Zoi.default(2)
          }),
        metadata: %{label: "team"},
        signal_source: "/team",
        routes: expected_routes
      })

    # Provider data and the topology each have a complete, independent literal
    # Map assertion in the extension suite. This comparison isolates core data.
    actual = %{definition | extensions: [], topology: %{agents: [], connections: []}}
    assert actual === expected
    assert Agent.define!(expected) === expected
    assert Enum.uniq(Map.values(targets)) |> length() == 3
  end

  test "full DSL lowers without Spark metadata and direct Map revalidation changes no field" do
    definition = Team.definition()
    assert Agent.define!(definition) === definition
    assert {:ok, ^definition} = Agent.validate(definition)
    assert Agent.definition?(definition)
    refute Agent.instance?(definition)

    assert Enum.map(definition.routes, & &1.path) == [
             "work.request",
             "plan.request",
             "work.done",
             "flow.request",
             "external.request",
             "external.clauses",
             "inline.request",
             "inline.emit",
             "partial.request",
             "unknown.request"
           ]

    assert Enum.all?(
             definition.routes,
             &(Map.keys(&1) |> Enum.sort() == Enum.sort([:path, :handler, :as, :defaults]))
           )

    assert [%Jido.Agent.DSL.Entry{__spark_metadata__: metadata} | _] =
             Spark.Dsl.Extension.get_entities(Team, [:__routes__])

    assert metadata != nil
    refute Map.has_key?(hd(definition.routes), :__spark_metadata__)

    for path <- ["inline.request", "inline.emit"] do
      expected_target = Jido.Action.Inline.target!(Team, host: Agent, route: path, role: :action)

      assert {:ok, %{handler: %{kind: :action, target: ^expected_target}}} =
               Route.select(definition, path)

      assert Jido.Instruction.validate(expected_target) == :ok
    end
  end

  for {field, value} <- [
        name: "",
        vsn: 0,
        module: true,
        description: :description,
        signal_source: "",
        metadata: [],
        routes: %{},
        topology: nil,
        extensions: %{}
      ] do
    test "invalid definition field #{field} is rejected" do
      assert {:error, %Error{}} =
               Agent.define(
                 Map.put(%{name: "invalid"}, unquote(field), unquote(Macro.escape(value)))
               )
    end
  end

  test "unknown fields, instance fields and live values cannot enter a definition" do
    for field <- [:kind, :definition, :outputs, :priority, :unknown] do
      assert {:error, %Error{code: :unknown_fields}} =
               Agent.define(Map.put(%{name: "test"}, field, nil))
    end

    assert {:error, %Error{code: :live_value}} =
             Agent.define(%{name: "test", metadata: %{pid: self()}})

    assert {:error, %Error{}} =
             Agent.define(%{name: "test", metadata: %{callback: fn -> :ok end}})

    assert {:error, %Error{}} = Agent.define(%{name: "test", kind: :instance})

    assert {:error, %Error{code: :invalid_agent}} =
             Agent.validate(%{kind: :definition, name: "partial"})
  end

  test "state schema must be static and cannot coerce or transform values" do
    for schema <- [
          Zoi.string(),
          Zoi.object(%{value: Zoi.integer(coerce: true)}),
          Zoi.object(%{value: Zoi.string() |> Zoi.transform(&String.trim/1)})
        ] do
      assert {:error, %Error{path: [:schema | _]}} =
               Agent.define(%{name: "test", schema: schema})
    end
  end

  test "definitions and instances use the same struct and differ only in identity and state" do
    definition = Named.definition()
    assert {:ok, instance} = Named.instantiate(id: "one")

    assert instance === %{definition | id: "one", state: %{value: "initial"}}

    assert Map.drop(Map.from_struct(instance), [:id, :state]) ===
             Map.drop(Map.from_struct(definition), [:id, :state])

    assert Agent.instance?(instance)
    refute Agent.definition?(instance)
    assert Agent.definition(instance) === definition
    assert Agent.definition(definition) === definition
    assert Agent.definition(Named) === definition
    assert {:ok, ^instance} = Agent.validate(instance)

    assert Named.instantiate!(id: "two", state: %{value: "supplied"}).state == %{
             value: "supplied"
           }

    assert {:error, %Error{path: [:id]}} = Named.instantiate()

    for state <- [%{value: 12}, %{extra: 1}, %{value: self()}] do
      assert {:error, %Error{}} = Named.instantiate(id: "bad", state: state)
    end

    assert {:error, %Error{code: :incomplete_state}} = Agent.validate(%{instance | state: %{}})
    assert {:error, %Error{}} = Agent.instantiate(instance, id: "nested")
  end

  test "input selection is exact unless a wildcard is explicit; declaration order wins" do
    broad = route("work.**", %{kind: :action, target: Action})
    exact = route("work.request")
    definition = Agent.define!(%{name: "ordered", routes: [broad, exact]})
    assert {:ok, ^broad} = Route.select(definition, "work.request")
    assert {:ok, ^broad} = Route.select(definition, "work.nested.request")
    assert {:error, %Error{code: :unmatched_input}} = Route.select(definition, "other.request")
    reverse = Agent.define!(%{name: "ordered", routes: [exact, broad]})
    assert {:ok, ^exact} = Route.select(reverse, "work.request")
    assert {:ok, ^broad} = Route.select(definition, "work.request")

    assert {:error, %Error{code: :unmatched_input}} =
             Route.select(Agent.define!(%{name: "empty"}), "work.request")
  end

  test "duplicate paths and helpers are errors, and helpers cannot use wildcards" do
    for routes <- [
          [route("work.request"), route("work.request")],
          [route("work.*"), route("work.*")],
          [
            route("work.one", %{kind: :action, target: Action}, as: :work),
            route("work.two", %{kind: :action, target: Action}, as: :work)
          ],
          [route("work.*", %{kind: :action, target: Action}, as: :work)]
        ] do
      assert {:error, %Error{}} = Agent.define(%{name: "bad", routes: routes})
    end
  end

  test "route target kinds are checked against the Action contract" do
    for handler <- [
          %{kind: :action, target: Flow},
          %{kind: :flow, target: Action},
          %{kind: :action, target: String},
          %{kind: :transform, target: {String, :not_exported, 1}},
          %{kind: :transform, target: fn signal -> signal end},
          %{kind: :topology},
          %{kind: :pass_through, target: Action}
        ] do
      assert {:error, %Error{path: [:routes, 0, :handler | _]}} =
               Agent.define(%{name: "bad", routes: [route("work.request", handler)]})
    end

    assert {:error, %Error{code: :unresolved_transform}} =
             Agent.define(%{
               name: "bad",
               routes: [
                 route("work.request", %{kind: :transform, target: {Unknown, :transform, 1}})
               ]
             })

    assert {:ok, _} =
             Agent.define(%{
               name: "adapter",
               routes: [
                 route("work.request", %{
                   kind: :transform,
                   target: {JidoTest.ComposableAgent.Adapter, :normalize, 1}
                 })
               ]
             })
  end

  test "defaults are shallow Action or Flow parameters, not state or signal mutation" do
    {:ok, route} = Route.select(Named.definition(), "work.request")
    assert Route.params(route, %{}) == {:ok, %{value: "default"}}
    assert Route.params(route, %{value: "input"}) == {:ok, %{value: "input"}}

    assert Route.params(%{route | defaults: %{nested: %{one: 1, two: 2}}}, %{nested: %{one: 3}}) ==
             {:ok, %{nested: %{one: 3}}}

    for handler <- [
          %{kind: :forward, target: %{kind: :parent}},
          %{kind: :transform, target: {JidoTest.ComposableAgent.Adapter, :normalize, 1}}
        ] do
      assert {:error, %Error{code: :invalid_defaults}} =
               Agent.define(%{
                 name: "bad",
                 routes: [route("work.request", handler, defaults: %{value: "x"})]
               })
    end
  end

  test "helpers construct the exact input Signal and require an explicit source" do
    assert {:ok, signal} = Named.work_signal(%{value: "caller"})
    assert %Jido.Signal{type: "work.request", source: "/named", data: %{value: "caller"}} = signal
    assert {:ok, %Jido.Signal{source: "/override"}} = Named.work_signal(%{}, source: "/override")
    definition = canonical()

    assert {:error, %Error{path: [:source]}} =
             Agent.input_signal(definition, "work.request", %{})

    assert {:ok, %Jido.Signal{type: "work.request"}} =
             Agent.input_signal(definition, "work.request", %{}, source: "/provided")
  end

  test "inline transforms retain the complete envelope and support guarded clauses" do
    definition = Team.definition()
    signal = Jido.Signal.new!("external.clauses", %{value: " hello "}, source: "/caller")
    {:ok, %{handler: %{target: {module, fun, 1}}}} = Route.select(definition, signal.type)
    assert {:ok, transformed} = apply(module, fun, [signal])
    assert transformed === %{signal | type: "work.request", data: %{value: "hello"}}

    assert {:ok, %Jido.Signal{data: %{value: "second"}}} =
             apply(module, fun, [%{signal | data: %{"value" => "second"}}])

    assert {:error, :invalid_value} = apply(module, fun, [%{signal | data: %{value: 5}}])
    {:ok, %{handler: %{target: {module, fun, 1}}}} = Route.select(definition, "partial.request")
    assert {:error, %Error{code: :transform_input}} = apply(module, fun, [%{signal | data: %{}}])
    assert {:ok, %Jido.Signal{type: "work.request"}} = apply(module, fun, [signal])
    {:ok, %{handler: %{target: {module, fun, 1}}}} = Route.select(definition, "external.request")
    assert {:ok, ^transformed} = apply(module, fun, [%{signal | data: %{value: "hello"}}])
  end

  test "unknown route fields and handler kinds fail during authoring" do
    assert {:error, %Error{code: :unknown_fields}} =
             Agent.define(%{
               name: "bad",
               routes: [Map.put(route("work.request"), :unknown, true)]
             })

    assert {:error, %Error{code: :invalid_handler}} =
             Agent.define(%{
               name: "bad",
               routes: [route("work.request", %{kind: :pass_through})]
             })
  end

  test "topology binds copied inputs and counts without creating another composition unit" do
    definition = Team.definition()

    assert {:ok, instance} =
             Agent.instantiate(definition,
               id: "team-one",
               state: %{value: "supplied", workers: 3}
             )

    assert {:ok, [planner, workers]} = Topology.bind(definition, instance.state)

    assert planner.name == :planner and planner.count == 1 and
             planner.state == %{value: "supplied"}

    assert workers.name == :workers and workers.count == 3 and
             workers.state == %{value: "supplied"}

    assert hd(definition.topology.agents).initial_state == %{value: %{kind: :state, key: :value}}
    assert {:error, %Error{}} = Team.instantiate(id: "bad", state: %{workers: 0})
    assert {:error, %Error{}} = Team.instantiate(id: "bad", state: %{workers: -1})
    assert {:ok, _} = Team.instantiate(id: "valid", state: %{workers: 1})
  end

  test "members reject duplicate names, root, missing fields, invalid counts and child state" do
    for agents <- [
          [member(), member()],
          [member(%{name: :root})],
          [member(%{count: 0})],
          [member(%{count: Topology.state(:missing)})],
          [member(%{initial_state: %{value: Topology.state(:missing)}})],
          [member(%{initial_state: %{value: 3}})],
          [member(%{initial_state: %{extra: "x"}})],
          [member(%{definition: Unknown})]
        ] do
      assert {:error, %Error{}} = composed(%{agents: agents})
    end

    inline = Worker.definition() |> Map.put(:module, nil)
    assert {:ok, definition} = composed(%{agents: [member(%{definition: inline})]})
    assert hd(definition.topology.agents).definition === inline
  end

  test "connections select all explicit matches, preserve order and never reroute inputs" do
    edges = [edge("work.request", :root, :worker), edge("work.*", :root, :worker)]
    assert {:ok, definition} = composed(%{agents: [member()], connections: edges})
    assert Topology.connections_for(definition, agent(:root), "work.request") == {:ok, edges}
    assert Topology.connections_for(definition, agent(:worker), "work.request") == {:ok, []}
    assert Enum.map(definition.topology.connections, & &1.path) == ["work.request", "work.*"]

    assert {:ok,
            [
              %{status: :unchecked, reason: :unknown_outputs},
              %{status: :unchecked, reason: :wildcard_coverage}
            ]} =
             Topology.checks(definition)

    assert {:error, %Error{code: :duplicate}} =
             composed(%{agents: [member()], connections: edges ++ [hd(edges)]})
  end

  test "connections require known immediate endpoints and explicit counted delivery" do
    assert {:error, %Error{code: :unknown_endpoint, path: [:topology, :connections, 0, :to]}} =
             composed(%{agents: [member()], connections: [edge("work.request", :root, :missing)]})

    for count <- [2, Topology.state(:workers)] do
      assert {:error, %Error{code: :counted_delivery}} =
               composed(%{
                 agents: [member(%{count: count})],
                 connections: [edge("work.request", :root, :worker)]
               })

      assert {:ok, _} =
               composed(%{
                 agents: [member(%{count: count})],
                 connections: [edge("work.request", :root, :worker, :broadcast)]
               })
    end

    assert {:error, %Error{}} =
             composed(%{
               agents: [member()],
               connections: [%{path: "work.request", from: :root, to: :worker}]
             })

    assert {:error, %Error{}} =
             composed(%{
               agents: [member()],
               connections: [edge("work.request", :root, :worker, :round_robin)]
             })
  end

  test "connection proofs reject unavailable inputs and mark outputs as unchecked" do
    assert {:error, %Error{code: :unaccepted_type}} =
             composed(%{agents: [member()], connections: [edge("unknown.type", :root, :worker)]})

    assert {:ok, definition} =
             composed(%{
               agents: [member()],
               connections: [edge("work.request", :worker, :worker)]
             })

    assert {:ok, [%{status: :unchecked, reason: :unknown_outputs}]} = Topology.checks(definition)

    assert {:ok, definition} =
             composed(%{agents: [member()], connections: [edge("work.done", :worker, :root)]})

    assert {:ok, [%{status: :unchecked, reason: :unknown_outputs}]} =
             Topology.checks(definition)
  end

  test "a team replaces a leaf through the same routes and explicit root outputs" do
    inner =
      Agent.define!(%{
        name: "inner",
        routes: [route("work.request"), route("work.done")],
        topology: %{
          agents: [member()],
          connections: [edge("work.request", :root, :worker), edge("work.done", :worker, :root)]
        }
      })

    wires = [edge("work.request", :root, :worker), edge("work.done", :worker, :root)]
    assert {:ok, leaf_parent} = composed(%{agents: [member()], connections: wires})

    assert {:ok, team_parent} =
             composed(%{agents: [member(%{definition: inner})], connections: wires})

    assert leaf_parent.topology.connections === team_parent.topology.connections
    assert {:ok, proofs} = Topology.checks(team_parent)
    assert Enum.all?(proofs, &(&1.status == :unchecked))
    assert {:ok, _} = Agent.instantiate(team_parent, id: "outer")

    without_input = %{inner | routes: [hd(inner.routes)]}
    assert {:error, %Error{code: :unaccepted_type}} = Agent.define(without_input)
  end

  test "nested literal inputs are checked even beside a symbolic state reference" do
    child =
      Agent.define!(%{
        name: "nested",
        schema: Zoi.object(%{settings: Zoi.object(%{value: Zoi.string(), limit: Zoi.integer()})})
      })

    initial = %{settings: %{value: Topology.state(:value), limit: "invalid"}}

    assert {:error, %Error{}} =
             composed(%{agents: [member(%{definition: child, initial_state: initial})]})

    valid = put_in(initial, [:settings, :limit], 3)

    assert {:ok, parent} =
             composed(%{agents: [member(%{definition: child, initial_state: valid})]})

    assert {:ok, instance} = Agent.instantiate(parent, id: "nested", state: %{value: "copied"})

    assert {:ok, [%{state: %{settings: %{value: "copied", limit: 3}}}]} =
             Topology.bind(parent, instance.state)

    assert {:error, %Error{}} =
             Agent.instantiate(child,
               id: "bad",
               state: %{settings: %{value: "test", limit: 3, unknown: true}}
             )
  end

  test "state initialization adds defaults without converting supplied values" do
    definition =
      Agent.define!(%{name: "static", schema: Zoi.object(%{values: Zoi.list(Zoi.integer())})})

    assert {:ok, %{state: %{values: [1, 2]}}} =
             Agent.instantiate(definition, id: "valid", state: %{values: [1, 2]})

    assert {:error, %Error{code: :state_conversion}} =
             Agent.instantiate(definition, id: "invalid", state: %{values: {1, 2}})
  end

  test "source provenance does not override directly authored definition fields" do
    input =
      Named.definition()
      |> Map.merge(%{
        name: "map-copy",
        metadata: %{owner: "map"},
        routes: [],
        schema: Zoi.object(%{})
      })

    assert Agent.define!(input) === input
    assert Agent.instantiate!(input, id: "map-instance").state == %{}
    assert input.module == Named
  end

  test "compile-time route loops produce distinct callable transform references" do
    module =
      Compiler.compile("""
      routes do
        for path <- ["first.request", "second.request"] do
          route path do
            transform signal do
              {:ok, signal}
            end
          end
        end
      end
      """)

    definition = module.definition()
    assert Enum.map(definition.routes, & &1.path) == ["first.request", "second.request"]
    assert Enum.uniq(Enum.map(definition.routes, & &1.handler.target)) |> length() == 2

    for route <- definition.routes do
      signal = Jido.Signal.new!(route.path, %{}, source: "/loop")
      {owner, function, 1} = route.handler.target
      assert {:ok, ^signal} = apply(owner, function, [signal])
    end
  end

  test "Map authoring never accepts the compiler's pending executable kind" do
    assert {:error, %Error{code: :invalid_handler}} =
             Agent.define(%{
               name: "bad",
               routes: [route("work.request", %{kind: :executable, target: Action})]
             })
  end

  test "DSL compile rejects conflicting handlers, old targets and duplicate core fields" do
    for body <- [
          "routes do route \"work.request\", priority: 2 end",
          "routes do route \"work.request\", JidoTest.ComposableAgent.Action do transform signal do {:ok,signal} end end end",
          "routes do route \"work.request\" do action value do {:ok,value} end; transform signal do {:ok,signal} end end end",
          "state do schema Zoi.object(%{}); schema Zoi.object(%{}) end",
          "state do end; state do end"
        ] do
      assert_raise CompileError, fn -> Compiler.compile(body) end
    end
  end

  test "related-definition failures stop the compiler instead of becoming Spark warnings" do
    for {body, message} <- [
          {"topology do agent :worker, JidoTest.ComposableAgent.NoSuchAgent end",
           "Member definition is not available"},
          {"routes do route \"missing.type\", JidoTest.ComposableAgent.Action end\ntopology do agent :worker, JidoTest.ComposableAgent.Worker; connections do connect \"missing.type\", from: :root,to: :worker end end",
           "Destination does not accept"}
        ] do
      {pid, monitor} = spawn_monitor(fn -> Compiler.compile(body) end)
      assert_receive {:DOWN, ^monitor, :process, ^pid, {%Error{message: error}, _stack}}, 5000
      assert error =~ message
    end
  end
end

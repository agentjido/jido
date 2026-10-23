defmodule JidoTest.Contract.AgentAuthoringTest do
  use Covenant.Case, component: "jido.agent", async: true
  alias Jido.Agent
  alias JidoTest.AgentContract, as: F

  defmodule Leaf do
    use Jido.Agent, name: "contract_leaf"

    state do
      schema Zoi.object(%{count: Zoi.integer() |> Zoi.default(0)})
    end

    routes do
      signal_source "/contract"

      route "work.request", JidoTest.AgentContract.Return, as: :work do
        state(from: output())
      end
    end
  end

  defmodule TypedLeaf do
    use Jido.Agent, name: "contract_typed_leaf"

    state do
      schema Zoi.object(%{count: Zoi.integer() |> Zoi.default(0)})
    end

    routes do
      signal_source "/contract"

      route "work.add", JidoTest.AgentContract.Add, as: :add do
        state(from: output())
      end
    end
  end

  defmodule InlineLeaf do
    use Jido.Agent, name: "contract_inline_leaf"

    routes do
      signal_source "/contract"

      route "work.inline", as: :work do
        action _input, output_schema: Zoi.map(), context: context do
          {:ok, context.agent_state}
        end

        state(from: output())
      end
    end
  end

  defmodule Child do
    use Jido.Agent, name: "contract_child"

    routes do
      route "work.request", JidoTest.AgentContract.Return do
        state(from: output())
      end
    end
  end

  defmodule CompleteDsl do
    use Jido.Agent,
      id: "tests/agents/complete-dsl",
      name: "contract_complete_dsl",
      description: "Complete core DSL shape",
      vsn: 2,
      metadata: %{domain: "contracts"}

    state do
      schema Zoi.object(%{count: Zoi.integer() |> Zoi.default(0)})
      initial_state %{count: 2}
    end

    plugins do
      plugin JidoTest.AgentContract.First, config: %{initial: 3}
    end

    routes do
      signal_source "/contract/complete"

      route "work.request", JidoTest.AgentContract.Return,
        as: :work,
        defaults: %{mode: :ok} do
        state(from: output())
      end
    end

    topology do
      agent :workers, Child, count: 2

      connections do
        connect "work.request", from: :root, to: :workers, delivery: :broadcast
      end
    end
  end

  defmodule RouteForms do
    use Jido.Agent, name: "contract_route_forms"

    state do
      schema Zoi.object(%{count: Zoi.integer() |> Zoi.default(0)})
    end

    routes do
      signal_source "/contract/routes"

      route "route.action", JidoTest.AgentContract.Return do
        state(:unchanged)
        reply("route.action.reply", from: output())
      end

      route "route.flow", JidoTest.AgentContract.Flow do
        state(from: output())
      end

      route "route.project", JidoTest.AgentContract.Project do
        state(from: output(:state))
        reply("route.project.reply", from: output([:reply, :value]))
      end

      route "route.inline_action" do
        action input, output_schema: Zoi.map() do
          {:ok, input}
        end

        state(from: output())
      end

      route "route.inline_flow" do
        flow schema: Zoi.object(%{amount: Zoi.integer()}),
             output_schema: Zoi.map() do
          step "add",
            action: JidoTest.AgentContract.Add,
            params: %{amount: input(:amount)}

          output result("add")
        end

        state(from: output())
      end

      route "route.forward" do
        forward(to: parent())
      end

      route "route.transform" do
        transform signal do
          {:ok, %{signal | type: "route.action"}}
        end
      end
    end
  end

  defp docs(module) do
    {:docs_v1, _annotation, :elixir, _format, _module_doc, _metadata, entries} =
      Code.fetch_docs(module)

    Map.new(entries, fn {{kind, name, arity}, _annotation, _signatures, doc, _metadata} ->
      {{kind, name, arity}, doc}
    end)
  end

  @tag obligation: "jido.agent.I1"
  test "independent Map and DSL declarations produce the same canonical Agent" do
    from_map =
      Agent.define!(%{
        name: "contract_leaf",
        module: Leaf,
        schema: Zoi.object(%{count: Zoi.integer() |> Zoi.default(0)}),
        signal_source: "/contract",
        routes: [
          %{
            path: "work.request",
            as: :work,
            handler: %{kind: :action, target: F.Return},
            state: %{source: :output, path: []}
          }
        ]
      })

    assert from_map === Leaf.definition()
    assert {:ok, ^from_map} = Zoi.parse(Agent.__schema__(), from_map)

    assert {:error, _issues} =
             Zoi.parse(Agent.__schema__(), %{from_map | name: "", vsn: 0})

    defaults = Agent.__defaults__()
    assert defaults.name == nil
    assert defaults.vsn == 1
    assert defaults.schema == Zoi.object(%{})
    assert defaults.topology == %{}

    complete =
      Agent.define!(%{
        module: CompleteDsl,
        name: "contract_complete_dsl",
        description: "Complete core DSL shape",
        vsn: 2,
        schema: Zoi.object(%{count: Zoi.integer() |> Zoi.default(0)}),
        initial_state: %{count: 2},
        metadata: %{domain: "contracts"},
        signal_source: "/contract/complete",
        routes: [
          %{
            path: "work.request",
            handler: %{kind: :action, target: F.Return},
            as: :work,
            defaults: %{mode: :ok},
            state: %{source: :output, path: []}
          }
        ],
        topology: %{
          agents: [%{name: :workers, definition: Child, count: 2}],
          connections: [
            %{
              path: "work.request",
              from: %{kind: :agent, name: :root},
              to: %{kind: :agent, name: :workers},
              delivery: :broadcast
            }
          ]
        },
        extensions: [F.contribution(F.First, %{initial: 3})]
      })

    assert complete === CompleteDsl.definition()
    assert CompleteDsl.__jido_authoring__().id == "tests/agents/complete-dsl"
  end

  @tag obligation: ["jido.agent.I2", "jido.agent.I3", "jido.agent.I7", "jido.agent.I9"]
  test "definitions are neutral and instances need explicit identity and complete stored state" do
    definition = Leaf.definition()
    assert definition.id == nil and definition.state == nil

    for attrs <- [%{id: "bad"}, %{state: %{}}, %{unknown: true}, %{vsn: 0}] do
      assert {:error, _} = Agent.define(Map.merge(Map.from_struct(definition), attrs))
    end

    for opts <- [[], [id: nil], [id: ""], [id: "leaf", name: "changed"]] do
      assert {:error, _} = Leaf.instantiate(opts)
    end

    assert {:ok, instance} = Leaf.instantiate(id: "leaf")
    assert instance.state == %{count: 0}
    assert {:error, _} = Agent.validate(%{instance | state: %{}})
    assert Agent.definition(instance) === definition
  end

  @tag obligation: ["jido.agent.I4", "jido.agent.I5"]
  test "duplicate declarations fail and instance reuse preserves order and exact values" do
    definition = Leaf.definition()
    route = hd(definition.routes)
    assert {:error, _} = Agent.define(%{definition | routes: [route, route]})

    assert {:error, %Agent.Error{code: :duplicate, path: [:routes]}} =
             Agent.define(%{
               definition
               | routes: [route, %{route | path: "work.other", as: route.as}]
             })

    for name <- [:Bad, :_private, :"bad name", :"bad-name", :bad!] do
      assert {:error,
              %Agent.Error{
                code: :invalid_helper_name,
                path: [:routes, 0, :as]
              }} = Agent.define(%{definition | routes: [%{route | as: name}]})
    end

    assert {:error, _} = Agent.define(name: "keywords_are_not_maps")
    left = Leaf.instantiate!(id: "left", state: %{count: 1})
    right = Leaf.instantiate!(id: "right", state: %{count: 2})
    assert Agent.definition(left) === Agent.definition(right)
    assert Leaf.definition() === definition
  end

  @tag obligation: ["jido.agent.I5", "jido.agent.I6", "jido.agent.I8"]
  test "a Map definition can provide reusable initial state" do
    definition =
      Agent.define!(%{
        name: "map_initial_state",
        schema:
          Zoi.object(%{
            count: Zoi.integer() |> Zoi.default(1),
            label: Zoi.string() |> Zoi.default("schema"),
            settings: Zoi.map() |> Zoi.default(%{source: :schema})
          }),
        initial_state: %{count: 2, settings: %{source: :definition}}
      })

    assert Agent.instantiate!(definition, id: "first").state === %{
             count: 2,
             label: "schema",
             settings: %{source: :definition}
           }

    assert Agent.instantiate!(definition,
             id: "second",
             state: %{count: 0, settings: %{source: :caller}}
           ).state === %{
             count: 0,
             label: "schema",
             settings: %{source: :caller}
           }

    assert definition.initial_state === %{count: 2, settings: %{source: :definition}}
    assert definition.id == nil and definition.state == nil
  end

  @tag obligation: ["jido.agent.I3", "jido.agent.I4"]
  test "the DSL rejects invalid identity, repeated core declarations, and unsafe helpers" do
    assert_raise Jido.Authoring.Registry.Error, ~r/Registry identifier/, fn ->
      F.with_agent("", fn _module -> :ok end, ~s(, id: "bad id"))
    end

    for body <- [
          "agent do end",
          "state do initial %{} end",
          "state do end\nstate do end",
          "plugins do end\nplugins do end",
          "routes do end\nroutes do end",
          "topology do end\ntopology do end",
          "state do schema Zoi.object(%{}); schema Zoi.object(%{}) end",
          "state do initial_state %{}; initial_state %{} end"
        ] do
      assert_raise CompileError, fn -> F.with_agent(body, fn _module -> :ok end) end
    end

    assert_raise Spark.Error.DslError, ~r/helper name/, fn ->
      F.with_agent(
        """
        routes do
          route "work.request", JidoTest.AgentContract.Return, as: :"bad name" do
            state from: output()
          end
        end
        """,
        fn _module -> :ok end
      )
    end

    assert_raise ArgumentError, ~r/unique keyword options/, fn ->
      F.with_agent("", fn _module -> :ok end, ~s(, name: "duplicate"))
    end
  end

  @tag obligation: "jido.agent.I8"
  test "initialization uses Zoi defaults and preserves supplied values" do
    definition =
      Agent.define!(%{
        name: "defaults",
        schema:
          Zoi.object(%{
            count: Zoi.integer() |> Zoi.default(1),
            enabled: Zoi.boolean() |> Zoi.default(true),
            note: Zoi.string() |> Zoi.nullable() |> Zoi.default("default"),
            settings: Zoi.map() |> Zoi.default(%{a: 1})
          })
      })

    assert {:ok, instance} =
             Agent.instantiate(definition,
               id: "defaults",
               state: %{count: 0, enabled: false, note: nil, settings: %{}}
             )

    assert instance.state === %{count: 0, enabled: false, note: "default", settings: %{}}
    assert {:error, _} = Agent.instantiate(definition, id: "defaults", state: %{count: "0"})
  end

  @tag obligation: ["jido.agent.I10", "jido.agent.I11"]
  test "Plugin state has one owner and domain updates use shallow replacement" do
    definition = F.definition(extensions: [F.contribution(F.First)])
    agent = Agent.instantiate!(definition, id: "plugin")
    assert agent.state.first == 0
    assert {:ok, state} = Zoi.parse(Agent.schema(agent), agent.state)
    assert state === agent.state
    assert {:error, _} = Agent.set(agent, first: 2)
    assert {:ok, next} = Agent.set(agent, settings: %{})
    assert next.state.settings == %{}
    assert agent.state.settings == %{a: 1, b: 2}

    assert {:error, _} =
             Agent.define(%{
               name: "collision",
               schema: Zoi.object(%{first: Zoi.integer()}),
               extensions: [F.contribution(F.First)]
             })

    assert {:error, _} =
             Agent.define(%{
               definition
               | extensions: definition.extensions ++ definition.extensions
             })
  end

  @tag obligation: "jido.agent.I20"
  test "the trusted JSON codec returns the portable definition" do
    assert Jido.Agent.Codec.__jido_authoring_codec__() == %{
             type: "jido.agent.definition",
             vsn: 2,
             encoder: Jido.Agent
           }

    for value <- [Leaf.definition(), Leaf.instantiate!(id: "json")] do
      registry = JidoTest.AgentRegistry.for(value)
      assert {:ok, _document} = JidoTest.AgentRegistry.encode(value, registry)
      assert {:ok, json} = JidoTest.AgentRegistry.encode_json(value, registry)
      expected = Agent.definition(value)
      assert {:ok, ^expected} = JidoTest.AgentRegistry.decode_json(json, registry)
    end

    assert {:error, _} = JidoTest.AgentRegistry.decode_json("{}", %{})
  end

  @tag obligation: "jido.agent.I21"
  test "Signal helpers preserve input and give tuple and raising forms" do
    assert {:ok, first} = Leaf.work_signal(%{})
    assert {:ok, second} = Leaf.work_signal(%{count: 2})
    assert bang = TypedLeaf.add_signal!(%{amount: "target validation is deferred"})
    assert first.type == "work.request" and first.source == "/contract"
    assert first.data == %{} and second.data == %{count: 2}
    assert bang.data == %{amount: "target validation is deferred"}
    assert {:error, _} = JidoTest.AgentContract.Add.validate_params(bang.data)
    assert first.id != second.id
    assert {:error, _} = Leaf.work_signal([])
    assert {:error, _} = Leaf.work_signal(%{}, type: "forged")
    assert {:error, _} = Leaf.work_signal(%{}, data: %{forged: true})
    assert_raise Agent.Error, fn -> Leaf.work_signal!([]) end
    assert_raise Agent.Error, fn -> Leaf.work_signal!(%{}, type: "forged") end
  end

  @tag obligation: ["jido.agent.I22", "jido.agent.I23"]
  test "invalid definitions return structured paths and bang forms raise the same error" do
    attrs = %{name: "invalid", routes: [%{path: "x", handler: %{kind: :missing}}]}
    assert {:error, %Agent.Error{path: [:routes, 0, :handler]} = error} = Agent.define(attrs)
    assert is_binary(error.message) and error.message != ""
    assert_raise Agent.Error, error.message, fn -> Agent.define!(attrs) end
    assert {:error, %Agent.Error{} = error} = Leaf.instantiate(id: "")
    assert_raise Agent.Error, error.message, fn -> Leaf.instantiate!(id: "") end
  end

  @tag obligation: "jido.agent.I24"
  test "the documented Agent facade has one constructor and validation path" do
    for {name, arity} <- [
          schema: 1,
          define: 1,
          define!: 1,
          validate: 1,
          definition?: 1,
          instance?: 1,
          definition: 1,
          instantiate: 1,
          instantiate: 2,
          instantiate!: 1,
          instantiate!: 2,
          mutate: 2,
          set: 2,
          cmd: 2,
          cmd: 3
        ] do
      assert function_exported?(Agent, name, arity)
    end

    api_docs = docs(Agent)
    assert {:ok, specs} = Code.Typespec.fetch_specs(Agent)

    for key <- [
          {:macro, :__using__, 1},
          {:function, :schema, 1},
          {:function, :define, 1},
          {:function, :define!, 1},
          {:function, :validate, 1},
          {:function, :definition?, 1},
          {:function, :instance?, 1},
          {:function, :definition, 1},
          {:function, :instantiate, 2},
          {:function, :instantiate!, 2},
          {:function, :mutate, 2},
          {:function, :set, 2},
          {:function, :cmd, 3}
        ] do
      assert is_map(Map.fetch!(api_docs, key))
    end

    for key <- [
          schema: 1,
          define: 1,
          define!: 1,
          validate: 1,
          definition?: 1,
          instance?: 1,
          definition: 1,
          instantiate: 2,
          instantiate!: 2,
          mutate: 2,
          set: 2,
          cmd: 3
        ] do
      assert List.keymember?(specs, key, 0)
    end

    for key <- [
          {:function, :__schema__, 0},
          {:function, :__defaults__, 0},
          {:function, :options!, 2},
          {:function, :runtime_plugins, 1},
          {:function, :validate_runtime_support, 1},
          {:function, :input_signal, 4},
          {:function, :input_signal!, 4},
          {:function, :transition, 2},
          {:function, :transition_validated, 3}
        ] do
      assert Map.fetch!(api_docs, key) == :hidden
    end

    for {name, arity} <- [
          new: 1,
          new!: 1,
          validate_instance: 1,
          complete_schema: 1,
          handle_signal: 2,
          checkpoint: 1,
          restore: 2
        ] do
      refute function_exported?(Agent, name, arity)
    end
  end

  @tag obligation: "jido.agent.I32"
  test "generated Agent modules expose one documented facade" do
    for {name, arity} <- [
          vsn: 0,
          schema: 0,
          definition: 0,
          instantiate: 0,
          instantiate: 1,
          instantiate!: 0,
          instantiate!: 1,
          cmd: 2,
          cmd: 3,
          route_executable!: 1
        ] do
      assert function_exported?(InlineLeaf, name, arity)
    end

    assert InlineLeaf.vsn() == InlineLeaf.definition().vsn
    assert InlineLeaf.schema() == Agent.schema(InlineLeaf.definition())
    assert {:ok, %Agent{module: InlineLeaf}} = InlineLeaf.instantiate(id: "generated-api")
    assert InlineLeaf.instantiate!(id: "generated-api-bang").module == InlineLeaf

    target = InlineLeaf.route_executable!("work.inline")

    assert {:ok, %Jido.Instruction{kind: :action, target: ^target}} =
             Jido.Instruction.resolve(target)

    assert_raise ArgumentError, fn -> InlineLeaf.route_executable!("missing") end
  end

  @tag obligation: "jido.agent.I32"
  test "all route body forms lower to the canonical Map contract" do
    routes = Map.new(RouteForms.definition().routes, &{&1.path, &1})
    root = %{source: :output, path: []}

    assert routes["route.action"] == %{
             path: "route.action",
             as: nil,
             defaults: %{},
             handler: %{kind: :action, target: F.Return},
             state: :unchanged,
             reply: %{type: "route.action.reply", from: root}
           }

    assert routes["route.flow"].handler == %{kind: :flow, target: F.Flow}
    assert routes["route.flow"].state == root

    assert routes["route.project"].state == %{source: :output, path: [:state]}

    assert routes["route.project"].reply == %{
             type: "route.project.reply",
             from: %{source: :output, path: [:reply, :value]}
           }

    assert routes["route.inline_action"].handler.kind == :action
    assert routes["route.inline_action"].state == root
    assert routes["route.inline_flow"].handler.kind == :flow
    assert routes["route.inline_flow"].state == root

    assert routes["route.forward"] == %{
             path: "route.forward",
             as: nil,
             defaults: %{},
             handler: %{kind: :forward, target: %{kind: :parent}},
             state: :unchanged,
             reply: nil
           }

    assert routes["route.transform"].handler.kind == :transform
    assert routes["route.transform"].state == :unchanged
    assert routes["route.transform"].reply == nil
    assert Agent.define!(Map.from_struct(RouteForms.definition())) == RouteForms.definition()
  end

  @tag obligation: "jido.agent.I32"
  test "route_executable returns referenced and inline Action and Flow targets" do
    for path <- [
          "route.action",
          "route.flow",
          "route.project",
          "route.inline_action",
          "route.inline_flow"
        ] do
      route = Enum.find(RouteForms.definition().routes, &(&1.path == path))
      assert RouteForms.route_executable!(path) == route.handler.target
    end

    assert RouteForms.route_executable!("route.inline_action") ==
             Jido.Action.Inline.target!(RouteForms,
               host: Jido.Agent,
               route: "route.inline_action",
               role: :action
             )

    assert RouteForms.route_executable!("route.inline_flow") ==
             Jido.Flow.Inline.target!(RouteForms,
               host: Jido.Agent,
               route: "route.inline_flow",
               role: :flow
             )

    refute function_exported?(RouteForms, :route_action!, 1)
  end

  @tag obligation: "jido.agent.I32"
  test "an inline Flow route returns its exact projected state and directives" do
    before = RouteForms.instantiate!(id: "inline-flow")
    signal = Jido.Signal.new!("route.inline_flow", %{amount: 4}, source: "/test")

    assert {:ok, after_agent, directives} = Agent.cmd(before, signal)
    assert after_agent.state === %{count: 4}
    assert directives === []
  end

  @tag obligation: "jido.agent.I32"
  test "route_executable rejects terminal handlers and unknown paths" do
    for path <- ["route.forward", "route.transform", "missing"] do
      assert_raise ArgumentError, fn -> RouteForms.route_executable!(path) end
    end
  end

  @tag obligation: "jido.agent.I32"
  test "route bodies reject invalid role combinations" do
    invalid = [
      "routes do route \"bad\" do state :unchanged end end",
      "routes do route \"bad\" do action input do {:ok, input} end; transform signal do {:ok, signal} end; state from: output() end end",
      "routes do route \"bad\", F.Return do state from: output(); action _ do {:ok, %{}} end end end",
      "routes do route \"bad\", F.Return do state :unchanged; state from: output() end end",
      "routes do route \"bad\", F.Return do state :unchanged; reply \"one\", from: output(); reply \"two\", from: output() end end",
      "routes do route \"bad\", F.Return do reply \"reply\", from: output() end end",
      "routes do route \"bad\" do forward to: parent(); state :unchanged end end",
      "routes do route \"bad\" do transform signal do {:ok, signal} end; reply \"reply\", from: output() end end",
      "routes do route \"bad\" do flow output_schema: Zoi.map() do output result(\"missing\") end; state from: output() end end",
      "routes do forward \"bad\", to: parent() end"
    ]

    for body <- invalid do
      assert_raise CompileError, fn -> F.with_agent(body, fn _module -> :ok end) end
    end
  end

  @tag obligation: "jido.agent.I25"
  test "one Agent owns immediate named members and logical output connections" do
    assert Leaf.definition().topology === %{agents: [], connections: []}

    assert {:ok, team, _} =
             Agent.mutate(Leaf.definition(), [
               Agent.Directive.agent_add(:workers, Leaf, count: 2),
               Agent.Directive.connection_add("work.request",
                 from: :root,
                 to: :workers,
                 delivery: :broadcast
               )
             ])

    assert {:ok, [%{status: :unchecked, reason: :unknown_outputs}]} =
             Agent.Topology.checks(team)

    assert {:error, _} = Agent.mutate(team, [Agent.Directive.agent_add(:root, Leaf)])

    assert {:error, _} =
             Agent.mutate(team, [
               Agent.Directive.connection_add("work.request", from: :workers, to: :workers)
             ])

    for key <- [:groups, :resources, :relationships, :includes, :imports, :exports] do
      assert {:error, _} = Agent.define(%{name: "removed", topology: %{key => []}})
    end

    refute Code.ensure_loaded?(Module.concat(Jido, "Topology"))
  end
end

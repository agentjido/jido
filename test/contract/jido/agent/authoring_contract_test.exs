defmodule JidoTest.Contract.AgentAuthoringTest do
  use Covenant.Case, component: "jido.agent", async: true
  alias Jido.Agent
  alias JidoTest.AgentContract, as: F

  defmodule Leaf do
    use Jido.Agent, name: "contract_leaf"

    agent do
      schema Zoi.object(%{count: Zoi.integer() |> Zoi.default(0)})
    end

    routes do
      signal_source "/contract"
      route "work.request", as: :work
    end
  end

  defmodule TypedLeaf do
    use Jido.Agent, name: "contract_typed_leaf"

    agent do
      schema Zoi.object(%{count: Zoi.integer() |> Zoi.default(0)})
    end

    routes do
      signal_source "/contract"
      route "work.add", JidoTest.AgentContract.Add, as: :add
    end
  end

  @tag obligation: "jido.agent.I1"
  test "independent Map and DSL declarations produce the same canonical Agent" do
    from_map =
      Agent.define!(%{
        name: "contract_leaf",
        module: Leaf,
        schema: Zoi.object(%{count: Zoi.integer() |> Zoi.default(0)}),
        signal_source: "/contract",
        routes: [%{path: "work.request", as: :work, handler: %{kind: :pass_through}}]
      })

    assert from_map === Leaf.definition()
    assert {:ok, ^from_map} = Zoi.parse(Agent.__schema__(), from_map)
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
    assert {:error, _} = Agent.define(name: "keywords_are_not_maps")
    left = Leaf.instantiate!(id: "left", state: %{count: 1})
    right = Leaf.instantiate!(id: "right", state: %{count: 2})
    assert Agent.definition(left) === Agent.definition(right)
    assert Leaf.definition() === definition
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
  test "the trusted JSON codec retains the complete definition and instance" do
    for value <- [Leaf.definition(), Leaf.instantiate!(id: "json")] do
      assert {:ok, _, registry} = Agent.Codec.encode(value)
      assert {:ok, json} = Agent.to_json(value, registry)
      assert {:ok, ^value} = Agent.from_json(json, registry)
    end

    assert {:error, _} = Agent.from_json("{}", %{})
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
  test "the public API has one constructor and validation path" do
    for {name, arity} <- [
          define: 1,
          define!: 1,
          instantiate: 2,
          instantiate!: 2,
          validate: 1,
          schema: 1,
          mutate: 2
        ] do
      assert function_exported?(Agent, name, arity)
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

    assert {:ok, [%{status: :compatible}]} = Agent.Topology.checks(team)
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

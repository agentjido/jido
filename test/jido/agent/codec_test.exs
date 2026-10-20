defmodule Jido.Agent.CodecTest do
  use Covenant.Case, component: "jido.agent", async: true
  alias Jido.Agent
  alias Jido.Agent.Codec
  alias Jido.Authoring.Registry
  alias JidoTest.AgentContract, as: F
  alias JidoTest.AgentFixtures.Add

  defmodule Work do
    use Jido.Action, name: "codec_work", schema: Zoi.object(%{})
    def run(_, context), do: {:ok, context.agent_state}
  end

  defmodule WorkFlow do
    use Jido.Flow, name: "codec_flow", schema: Zoi.object(%{})

    flow do
      step "work", action: Work, params: %{}
      output result("work")
    end
  end

  defmodule Child do
    use Jido.Agent, name: "codec_child"

    agent do
      schema Zoi.object(%{value: Zoi.string() |> Zoi.default("default")})
    end

    routes do
      route "child.single"
      route "child.broadcast"
    end
  end

  def transform(signal), do: {:ok, signal}

  defmodule ChangingTarget do
    @behaviour Jido.Action
    def __jido_authoring_kind__, do: Process.get({__MODULE__, :kind}, :action)
    @impl true
    def validate_params(value), do: {:ok, value}
    @impl true
    def validate_output(value), do: {:ok, value}
    @impl true
    def run(_, _), do: raise("encoding must not run Actions")
  end

  @tag obligation: "jido.agent.I20"
  test "Codec retains route defaults and writes definitions only" do
    for defaults <- [%{}, %{by: 2}] do
      definition =
        Agent.define!(%{
          name: "defaults",
          routes: [
            %{path: "counter.add", handler: %{kind: :action, target: Add}, defaults: defaults}
          ]
        })

      registry = registry(definition, Add)

      for value <- [definition, Agent.instantiate!(definition, id: "encoded")] do
        assert {:ok, document} = Codec.encode(value, registry)
        assert document["type"] == "jido.agent.definition"
        refute Map.has_key?(document["definition"], "id")
        refute Map.has_key?(document["definition"], "state")

        expected = Agent.definition(value)
        assert {:ok, ^expected} = Codec.decode(JSON.decode!(JSON.encode!(document)), registry)
      end

      [route] = definition.routes

      for invalid <- [false, 1, "invalid", [], {1, 2}, %URI{}] do
        assert {:error, %{path: [:routes, 0, :defaults]}} =
                 Codec.encode(%{definition | routes: [%{route | defaults: invalid}]}, registry)
      end
    end
  end

  @tag obligation: "jido.agent.I20"
  test "Codec validates the current executable kind" do
    definition =
      Agent.define!(%{
        name: "changing_target",
        routes: [%{path: "counter.route", handler: %{kind: :action, target: ChangingTarget}}]
      })

    registry = registry(definition, ChangingTarget)
    Process.put({ChangingTarget, :kind}, :flow)

    for result <- [Codec.encode(definition, registry)] do
      assert {:error, %{code: :invalid_executable, path: [:routes, 0, :handler]}} = result
    end
  end

  @tag obligation: "jido.agent.I20"
  test "Codec rejects the old Agent envelope" do
    definition = Agent.define!(%{name: "new_document"})
    registry = registry(definition, nil)

    assert {:error, _error} =
             Codec.decode(%{"type" => "jido.agent", "version" => 1, "agent" => %{}}, registry)
  end

  @tag obligation: "jido.agent.I20"
  test "Codec preserves every portable Agent field and nested variant" do
    nested =
      Agent.define!(%{
        name: "nested",
        routes: [%{path: "child.single", handler: %{kind: :pass_through}}]
      })

    definition =
      Agent.define!(%{
        name: "complete_codec",
        description: "all portable fields",
        vsn: 3,
        schema: Zoi.object(%{count: Zoi.integer() |> Zoi.default(0)}),
        metadata: %{owner: :codec},
        signal_source: "/codec",
        routes: [
          %{
            path: "child.single",
            handler: %{kind: :action, target: Work},
            emits: ["child.single"]
          },
          %{path: "flow.run", handler: %{kind: :flow, target: WorkFlow}, emits: []},
          %{
            path: "transform.run",
            handler: %{kind: :transform, target: {__MODULE__, :transform, 1}},
            emits: ["transform.run"]
          },
          %{path: "child.broadcast", handler: %{kind: :pass_through}}
        ],
        topology: %{
          agents: [
            %{
              name: :literal,
              definition: nested,
              count: 1,
              initial_state: %{},
              identities: %{1 => "literal-1"}
            },
            %{
              name: :module,
              definition: Child,
              count: 2,
              initial_state: %{value: "seed"},
              identities: %{1 => "module-1", 2 => "module-2"}
            }
          ],
          connections: [
            %{
              path: "child.single",
              from: %{kind: :agent, name: :root},
              to: %{kind: :agent, name: :literal},
              delivery: :single
            },
            %{
              path: "child.broadcast",
              from: %{kind: :agent, name: :root},
              to: %{kind: :agent, name: :module},
              delivery: :broadcast
            }
          ]
        },
        extensions: [F.contribution(F.First, %{initial: 2})]
      })

    registry = JidoTest.AgentRegistry.for(definition)
    assert {:ok, document} = Codec.encode(definition, registry)
    assert {:ok, ^definition} = Codec.decode(JSON.decode!(JSON.encode!(document)), registry)
    assert {:ok, ^document} = Codec.encode(Map.from_struct(definition), registry)
    assert {:ok, child_document} = Codec.encode(Child, JidoTest.AgentRegistry.for(Child))
    assert child_document["definition"]["module"] != nil

    plugin_registry =
      registry.entries
      |> Map.new(fn
        {id, {:extension, F.First}} -> {id, {:plugin, F.First}}
        entry -> entry
      end)
      |> Registry.new!()

    assert {:ok, plugin_document} = Codec.encode(definition, plugin_registry)
    assert {:ok, ^definition} = Codec.decode(plugin_document, plugin_registry)
    assert {:error, %{code: :unknown_reference}} = Codec.encode(definition, %{})
  end

  @tag obligation: "jido.agent.I20"
  test "Codec rejects malformed values at each document boundary" do
    child =
      Agent.define!(%{
        name: "nested_shape",
        schema: Zoi.object(%{value: Zoi.string() |> Zoi.default("default")}),
        routes: [%{path: "child.single", handler: %{kind: :pass_through}}]
      })

    definition =
      Agent.define!(%{
        name: "codec_shape",
        routes: [%{path: "child.single", handler: %{kind: :action, target: Work}}],
        topology: %{
          agents: [%{name: :child, definition: child, initial_state: %{value: "seed"}}],
          connections: [
            %{
              path: "child.single",
              from: %{kind: :agent, name: :root},
              to: %{kind: :agent, name: :child}
            }
          ]
        },
        extensions: [F.contribution(F.First)]
      })

    registry = JidoTest.AgentRegistry.for(definition)
    {:ok, document} = Codec.encode(definition, registry)

    [route] = document["definition"]["routes"]
    [member] = document["definition"]["topology"]["agents"]
    [connection] = document["definition"]["topology"]["connections"]
    [extension] = document["definition"]["extensions"]

    invalid = [
      Map.put(document, "type", "unknown"),
      Map.delete(document, "version"),
      put_in(document, ["definition", "routes"], false),
      put_in(document, ["definition", "routes"], [%{"path" => "child.single"}]),
      put_in(document, ["definition", "routes"], [%{route | "handler" => %{"kind" => "bad"}}]),
      put_in(document, ["definition", "routes"], [
        %{route | "handler" => Map.put(route["handler"], "extra", true)}
      ]),
      put_in(document, ["definition", "routes"], [
        %{route | "handler" => %{"kind" => "pass_through", "extra" => true}}
      ]),
      put_in(document, ["definition", "topology"], false),
      put_in(document, ["definition", "topology", "agents"], false),
      put_in(
        document,
        ["definition", "topology", "agents"],
        [Map.delete(member, "name")]
      ),
      put_in(document, ["definition", "topology", "agents"], [
        %{member | "definition" => 1}
      ]),
      put_in(document, ["definition", "topology", "agents"], [
        %{member | "definition" => Map.put(member["definition"], "extra", true)}
      ]),
      put_in(
        document,
        ["definition", "topology", "connections"],
        [%{connection | "delivery" => "multicast"}]
      ),
      put_in(document, ["definition", "extensions"], [Map.put(extension, "extra", true)]),
      put_in(document, ["definition", "extensions"], [false]),
      put_in(document, ["definition", "extensions"], [
        %{extension | "provider" => %{"$type" => "reference"}}
      ])
    ]

    for value <- invalid, do: assert({:error, _} = Codec.decode(value, registry))

    for source <- [nil, [], %URI{}], do: assert({:error, _} = Codec.encode(source, registry))

    at_limit = Jason.encode!(String.duplicate("x", 8_388_606))
    over_limit = Jason.encode!(String.duplicate("x", 8_388_607))
    assert byte_size(at_limit) == 8_388_608
    assert byte_size(over_limit) == 8_388_609
    assert {:error, %{code: :invalid_document}} = Codec.from_json(at_limit, registry)

    for json <- [nil, "{", over_limit] do
      assert {:error, _} = Codec.from_json(json, registry)
    end
  end

  defp registry(definition, target) do
    entries = %{
      "schemas/agent/v1" => {:schema, definition.schema},
      "atoms/by" => {:atom, :by}
    }

    entries =
      if target, do: Map.put(entries, "actions/target/v1", {:action, target}), else: entries

    Registry.new!(entries)
  end
end

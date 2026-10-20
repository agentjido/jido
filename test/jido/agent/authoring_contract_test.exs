defmodule Jido.Agent.AuthoringContractTest do
  use Covenant.Case, component: "jido.agent", async: true
  alias Jido.Agent
  alias Jido.Agent.Authoring
  alias JidoTest.AgentFixtures.Add

  defmodule Factory do
    def new, do: Agent.define!(%{name: "factory"})
  end

  defmodule NoRuntime do
    use Jido.Agent.Extension, id: "test.agent.no_runtime"
  end

  defmodule MissingRuntime do
    use Jido.Agent.Extension, id: "test.agent.missing_runtime"
    def runtime_support, do: Module.concat(__MODULE__, MissingAdapter)
  end

  defmodule InvalidRuntime do
    use Jido.Agent.Extension, id: "test.agent.invalid_runtime"
    def runtime_support, do: String
  end

  defmodule ValidRuntime do
    use Jido.Agent.Extension, id: "test.agent.valid_runtime"
    def runtime_support, do: JidoTest.AgentContract.Stateless
  end

  @tag obligation: ["jido.agent.I4", "jido.agent.I7", "jido.agent.I11"]
  test "Map authoring and instance options reject ambiguous duplicates" do
    assert {:error, %{code: :invalid_map}} = Agent.define(name: "first", name: "last")
    definition = Agent.define!(%{name: "state", schema: Zoi.object(%{count: Zoi.integer()})})

    assert {:error, %{code: :invalid_options, message: message}} =
             Agent.instantiate(definition, id: "a", id: "b")

    assert message != ""
    instance = Agent.instantiate!(definition, id: "state", state: %{count: 0})
    assert {:ok, %{state: %{count: 2}}} = Agent.set(instance, count: 1, count: 2)

    for value <- [~D[2026-09-07], [:invalid], [key: 1] ++ [:invalid], [1 | :tail]] do
      assert {:error, _} = Agent.set(instance, value)
      assert {:error, _} = Agent.instantiate(definition, value)
    end
  end

  @tag obligation: ["jido.agent.I3", "jido.agent.I4", "jido.agent.I22"]
  test "authoring containers normalize keys and reject ambiguous input" do
    assert Authoring.key_identity(:name) === "name"
    assert Authoring.key_identity("name") === "name"
    assert {:ok, %{name: "agent"}} = Authoring.attrs(%{name: "agent"})
    assert {:ok, %{name: "agent"}} = Authoring.attrs(name: "agent")
    assert {:ok, %{name: "last"}} = Authoring.to_attrs(name: "first", name: "last")
    assert :error = Authoring.to_attrs([name: "first", name: "last"], :reject)

    for value <- [[name: "first", name: "last"], [:invalid], [1 | :tail]] do
      assert {:error, error} = Authoring.attrs(value)
      assert error.message != ""
      assert error.details.value === value
    end

    assert {:error, error} = Authoring.attrs(:invalid)
    assert error.message != ""
    assert error.details.value === :invalid
  end

  @tag obligation: ["jido.agent.I3", "jido.agent.I22"]
  test "authoring traversal preserves order and stops at one structured error" do
    assert :ok = Authoring.keys(%{name: "agent"}, [:name])

    assert {:error, error} = Authoring.keys(%{name: "agent", extra: true}, [:name])
    assert error.message != ""
    assert error.details.keys === [:extra]

    assert {:ok, [2, 4, 6]} = Authoring.traverse([1, 2, 3], &{:ok, &1 * 2})
    expected = Authoring.error("Stopped", %{at: 2})

    assert ^expected =
             Authoring.traverse([1, 2, 3], fn
               2 -> expected
               value -> {:ok, value}
             end)

    assert {:error, improper} = Authoring.traverse([1 | :tail], &{:ok, &1})
    assert improper.message != ""
    assert Authoring.unwrap!({:ok, :value}) === :value
    assert_raise Jido.Error.ValidationError, fn -> Authoring.unwrap!(expected) end
  end

  @tag obligation: ["jido.agent.I1", "jido.agent.I4"]
  test "routes accept one module with separate plain Map defaults" do
    for defaults <- [%{}, %{by: 2}] do
      assert {:ok, definition} = Agent.define(%{name: "routes", routes: [route(Add, defaults)]})
      assert [%{handler: %{target: Add, kind: :action}, defaults: ^defaults}] = definition.routes
    end

    for target <- [[], [Add], {Add, %{}}] do
      assert {:error, _} = Agent.define(%{name: "routes", routes: [route(target, %{})]})
    end

    for defaults <- [nil, [], [by: 1], %URI{}] do
      assert {:error, %{path: [:routes, 0, :defaults]}} =
               Agent.define(%{name: "routes", routes: [route(Add, defaults)]})
    end
  end

  @tag obligation: ["jido.agent.I2", "jido.agent.I22"]
  test "module provenance does not make a factory an Agent definition source" do
    assert {:error, %{code: :unresolved_definition}} = Agent.instantiate(Factory, id: "factory")
    assert {:ok, definition} = Agent.define(%{name: "origin", module: Factory})
    assert definition.module == Factory
  end

  @tag obligation: "jido.agent.I20"
  test "portable definitions reject arbitrary values and obsolete Registry kinds" do
    definition =
      Agent.define!(%{
        name: "registry",
        metadata: %{a: [:repeat, %URI{port: 1}, :repeat, %URI{port: 1.0}], b: {:last, <<255>>}},
        routes: [route(Add, %{by: 1})]
      })

    assert {:error, %Jido.Authoring.Value.Error{reason: :value}} =
             Agent.Codec.encode(definition, JidoTest.AgentRegistry.for(definition))

    for entry <- [{:value, %URI{}}, {:route_match, &is_map/1}] do
      assert {:error, _error} = Jido.Agent.Codec.Registry.new(%{"obsolete" => entry})
    end
  end

  @tag obligation: ["jido.agent.I2", "jido.agent.I7", "jido.agent.I24"]
  test "definition and instance predicates accept only their exact value shapes" do
    definition = Agent.define!(%{name: "predicate"})
    instance = Agent.instantiate!(definition, id: "x")

    assert definition.vsn === 1
    assert Agent.definition?(definition) === true
    assert Agent.instance?(definition) === false
    assert Agent.definition?(instance) === false
    assert Agent.instance?(instance) === true
    assert Agent.definition(definition) === definition

    for value <- [
          %{instance | id: ""},
          %{instance | id: 1},
          %{instance | state: nil},
          %{instance | state: []},
          %{instance | state: %URI{}},
          %{},
          nil
        ] do
      assert Agent.instance?(value) === false
    end

    for value <- [%{definition | id: "one"}, %{definition | state: %{}}, %{}, nil] do
      assert Agent.definition?(value) === false
    end

    assert {:error,
            %Jido.Error.ValidationError{
              message: "Agent.set/2 requires an instance",
              details: %{id: nil, state: nil}
            }} = Agent.set(definition, %{})
  end

  @tag obligation: "jido.agent.I10"
  test "runtime Plugin projection accepts only available Plugin adapters" do
    passive = %{
      id: NoRuntime.id(),
      provider: NoRuntime,
      vsn: NoRuntime.vsn(),
      data: %{}
    }

    definition = Agent.define!(%{name: "passive", extensions: [passive]})
    assert Agent.runtime_plugins(definition) === []
    assert Agent.validate_runtime_support(definition) === :ok

    valid = %{
      id: ValidRuntime.id(),
      provider: ValidRuntime,
      vsn: ValidRuntime.vsn(),
      data: %{}
    }

    supported = Agent.define!(%{name: "supported", extensions: [valid]})

    assert Agent.runtime_plugins(supported) === [{JidoTest.AgentContract.Stateless, []}]
    assert Agent.validate_runtime_support(supported) === :ok

    for provider <- [MissingRuntime, InvalidRuntime] do
      contribution = %{
        id: provider.id(),
        provider: provider,
        vsn: provider.vsn(),
        data: %{}
      }

      invalid = Agent.define!(%{name: "invalid", extensions: [contribution]})
      assert Agent.runtime_plugins(invalid) === []

      assert {:error,
              %Agent.Error{
                code: :runtime_support_not_available,
                path: [:extensions],
                details: %{provider: ^provider}
              }} = Agent.validate_runtime_support(invalid)
    end
  end

  @tag obligation: "jido.agent.I21"
  test "Signal construction preserves every supported envelope option" do
    definition = Agent.define!(%{name: "signal", signal_source: "/default"})
    time = ~U[2026-10-20 12:00:00Z]

    assert {:ok, signal} =
             Agent.input_signal(definition, "work", %{},
               source: "/explicit",
               id: "signal-id",
               time: time,
               subject: "worker",
               datacontenttype: "application/json"
             )

    assert signal.source == "/explicit"
    assert signal.id == "signal-id"
    assert signal.time == DateTime.to_iso8601(time)
    assert signal.subject == "worker"
    assert signal.datacontenttype == "application/json"
  end

  defp route(target, defaults),
    do: %{path: "counter.add", handler: %{kind: :action, target: target}, defaults: defaults}
end

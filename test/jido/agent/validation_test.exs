defmodule Jido.Agent.ValidationTest do
  use Covenant.Case, component: "jido.agent", async: true

  alias Jido.Agent
  alias Jido.Agent.Validation

  defmodule CallbackPlugin do
    use Jido.Plugin

    @impl true
    defdelegate state_spec(opts), to: Jido.Agent.ValidationTest.CallbackPlugin.Agent

    @impl true
    defdelegate directives(opts), to: Jido.Agent.ValidationTest.CallbackPlugin.Agent
  end

  defmodule CallbackPlugin.Agent do
    @behaviour Jido.Plugin

    @impl true
    def state_spec(opts) do
      send(self(), {:callback, :state_spec, opts})
      :none
    end

    @impl true
    def directives(opts) do
      send(self(), {:callback, :directives, opts})
      []
    end
  end

  defmodule StatePlugin do
    use Jido.Plugin

    @impl true
    defdelegate state_spec(opts), to: Jido.Agent.ValidationTest.StatePlugin.Agent
  end

  defmodule StatePlugin.Agent do
    @behaviour Jido.Plugin

    @impl true
    def state_spec(_opts), do: {:owned, Zoi.integer()}
  end

  defmodule InvalidSchemaPlugin do
    use Jido.Plugin

    @impl true
    def state_spec(_opts), do: {:owned, Zoi.integer(coerce: true)}
  end

  @tag obligation: "jido.agent.I10"
  test "Plugin ownership conflicts remain structured validation errors" do
    assert {:error, %Jido.Error.ValidationError{} = reason} =
             Agent.define(%{
               name: "conflict",
               schema: Zoi.object(%{owned: Zoi.integer()}),
               plugins: [entry(StatePlugin)]
             })

    assert Exception.message(reason) =~ "conflicts"
  end

  @tag obligation: ["jido.agent.I2", "jido.agent.I3"]
  test "neutral definitions use explicit canonical defaults" do
    assert {:ok, definition} = Agent.define(%{name: "defaults"})

    assert definition === %Agent{
             name: "defaults",
             id: nil,
             state: nil,
             module: nil,
             description: nil,
             vsn: 1,
             schema: Zoi.object(%{}),
             initial_state: %{},
             plugins: [],
             routes: [],
             signal_source: nil,
             topology: %{agents: [], connections: []},
             metadata: %{}
           }

    assert Agent.define(%{name: "defaults", id: nil, state: nil, description: nil}) ==
             {:ok, definition}

    for field <- [:name, :schema, :plugins, :routes, :metadata, :topology] do
      assert {:error, _} = Agent.define(Map.put(%{name: "defaults"}, field, nil))
    end
  end

  @tag obligation: ["jido.agent.I3", "jido.agent.I6"]
  test "initial state must be a plain static Map" do
    for initial_state <- [nil, [], %URI{}, %{process: self()}] do
      assert {:error, %Agent.Error{path: [:initial_state]}} =
               Agent.define(%{name: "invalid_initial_state", initial_state: initial_state})
    end
  end

  @tag obligation: ["jido.agent.I2", "jido.agent.I3"]
  test "unknown fields and instance data fail before provider callbacks" do
    attrs = %{name: nil, id: "instance", state: %{}, plugins: [entry(CallbackPlugin)]}
    assert {:error, %{code: :unknown_fields}} = Agent.define(Map.put(attrs, :extra, true))
    assert {:error, %{code: :definition_required}} = Agent.define(attrs)
    refute_received {:callback, _, _}
  end

  @tag obligation: ["jido.agent.I3", "jido.agent.I7"]
  test "unknown nil keys fail in every authoring boundary" do
    attrs = %{nil => :unexpected, name: "nil_key", plugins: [entry(CallbackPlugin)]}

    for input <- [attrs, Enum.to_list(attrs)] do
      assert {:error, _} = Agent.define(input)
      refute_received {:callback, _, _}
    end

    definition = Agent.define!(%{name: "nil_key"})

    for input <- [%{nil => :unexpected, id: "instance"}, [{nil, :unexpected}, {:id, "instance"}]] do
      assert {:error, %{code: :unknown_fields}} = Agent.instantiate(definition, input)
    end
  end

  @tag obligation: ["jido.agent.I3", "jido.agent.I22"]
  test "field validation follows one fixed order" do
    failures = [
      name: nil,
      module: true,
      description: 123,
      vsn: 0,
      schema: nil,
      metadata: nil,
      signal_source: ""
    ]

    for index <- 0..(length(failures) - 1) do
      {field, value} = Enum.at(failures, index)
      assert {:error, expected} = Agent.define(Map.put(%{name: "order"}, field, value))
      assert expected.message != ""

      assert {:error, actual} =
               Agent.define(Map.merge(%{name: "order"}, Map.new(Enum.drop(failures, index))))

      assert actual === expected
    end
  end

  @tag obligation: "jido.agent.I10"
  test "Plugin schema callbacks receive their current config" do
    assert {:ok, definition} =
             Agent.define(%{
               name: "callbacks",
               plugins: [entry(CallbackPlugin, %{label: :first})]
             })

    assert Agent.runtime_plugins(definition) == [{CallbackPlugin, [label: :first]}]
    assert_received {:callback, :state_spec, [label: :first]}
    assert_received {:callback, :directives, [label: :first]}

    instance = %{definition | id: "callbacks", state: %{}}
    assert {:ok, ^instance} = Agent.validate(instance)
    assert_received {:callback, :state_spec, [label: :first]}
    assert_received {:callback, :directives, [label: :first]}
    refute_received {:callback, :state_spec, _}
    refute_received {:callback, :directives, _}

    assert {:error, %{path: [:schema]}} = Agent.define(%{name: "bad_schema", schema: nil})
  end

  @tag obligation: ["jido.agent.I26", "jido.agent.I29"]
  test "internal definition passes can defer Plugin schema validation" do
    attrs = %{name: "deferred", plugins: [entry(InvalidSchemaPlugin)]}

    assert {:error, _} = Validation.define(attrs)
    assert {:ok, _} = Validation.define(attrs, related?: false)
    assert {:ok, _} = Validation.define(attrs, plugin_schema?: false)
  end

  @tag obligation: ["jido.agent.I2", "jido.agent.I7", "jido.agent.I22"]
  test "validation distinguishes definitions, instances, and unsupported values" do
    definition = Agent.define!(%{name: "validation_shapes"})

    assert {:error, %Agent.Error{code: :invalid_map, path: [:state], message: message}} =
             Agent.validate(%{definition | id: "instance"})

    assert message != ""

    assert {:error, %Agent.Error{code: :invalid_string, path: [:id], message: message}} =
             Agent.validate(%{definition | state: %{}})

    assert message != ""

    assert {:error, %Agent.Error{code: :invalid_agent, message: message}} =
             Agent.validate(:invalid)

    assert message != ""

    assert {:error, %Agent.Error{code: :definition_required, message: message}} =
             Validation.validate_definition(%{definition | id: "instance"})

    assert message != ""

    assert {:error, %Agent.Error{code: :instance_required, message: message}} =
             Validation.validate_instance_with_plugins(:invalid)

    assert message != ""
  end

  @tag obligation: ["jido.agent.I2", "jido.agent.I22"]
  test "noncanonical definitions return one nonempty normalization error" do
    definition = Agent.define!(%{name: "noncanonical"})

    assert {:error, %Agent.Error{code: :not_canonical, message: message}} =
             Validation.validate_definition(%{definition | topology: %{}})

    assert message != ""
  end

  defp entry(provider, data \\ %{}),
    do: %{id: provider.id(), provider: provider, vsn: provider.vsn(), data: data}
end

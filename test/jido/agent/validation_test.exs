defmodule Jido.Agent.ValidationTest do
  use ExUnit.Case, async: true

  alias Jido.Agent

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

  test "Plugin ownership conflicts remain structured validation errors" do
    assert {:error, %Jido.Error.ValidationError{} = reason} =
             Agent.define(%{
               name: "conflict",
               schema: Zoi.object(%{owned: Zoi.integer()}),
               extensions: [entry(StatePlugin)]
             })

    assert Exception.message(reason) =~ "conflicts"
  end

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
             extensions: [],
             routes: [],
             signal_source: nil,
             topology: %{agents: [], connections: []},
             metadata: %{}
           }

    assert Agent.define(%{name: "defaults", id: nil, state: nil, description: nil}) ==
             {:ok, definition}

    for field <- [:name, :schema, :extensions, :routes, :metadata, :topology] do
      assert {:error, _} = Agent.define(Map.put(%{name: "defaults"}, field, nil))
    end
  end

  test "unknown fields and instance data fail before provider callbacks" do
    attrs = %{name: nil, id: "instance", state: %{}, extensions: [entry(CallbackPlugin)]}
    assert {:error, %{code: :unknown_fields}} = Agent.define(Map.put(attrs, :extra, true))
    assert {:error, %{code: :definition_required}} = Agent.define(attrs)
    refute_received {:callback, _, _}
  end

  test "unknown nil keys fail in every authoring boundary" do
    attrs = %{nil => :unexpected, name: "nil_key", extensions: [entry(CallbackPlugin)]}

    for input <- [attrs, Enum.to_list(attrs)] do
      assert {:error, _} = Agent.define(input)
      refute_received {:callback, _, _}
    end

    definition = Agent.define!(%{name: "nil_key"})

    for input <- [%{nil => :unexpected, id: "instance"}, [{nil, :unexpected}, {:id, "instance"}]] do
      assert {:error, %{code: :unknown_fields}} = Agent.instantiate(definition, input)
    end
  end

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

      assert {:error, actual} =
               Agent.define(Map.merge(%{name: "order"}, Map.new(Enum.drop(failures, index))))

      assert actual === expected
    end
  end

  test "Plugin schema callbacks receive their current config" do
    assert {:ok, definition} =
             Agent.define(%{
               name: "callbacks",
               extensions: [entry(CallbackPlugin, %{label: :first})]
             })

    assert Agent.runtime_plugins(definition) == [{CallbackPlugin, [label: :first]}]
    assert_received {:callback, :state_spec, [label: :first]}
    assert_received {:callback, :directives, [label: :first]}
    assert {:error, %{path: [:schema]}} = Agent.define(%{name: "bad_schema", schema: nil})
  end

  defp entry(provider, data \\ %{}),
    do: %{id: provider.id(), provider: provider, vsn: provider.vsn(), data: data}
end

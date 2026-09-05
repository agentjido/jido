defmodule Jido.Agent.ValidationTest do
  use ExUnit.Case, async: true

  alias Jido.Agent
  alias Jido.Error.ValidationError

  defmodule CallbackPlugin do
    use Jido.Plugin

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
    def state_spec(_opts), do: {:owned, Zoi.integer()}
  end

  test "checks Plugin schema composition before routes and metadata" do
    assert {:error,
            %ValidationError{
              message: "Agent Plugin state key conflicts with the Agent domain schema"
            }} =
             Agent.new(
               name: "conflict",
               schema: Zoi.object(%{owned: Zoi.integer()}),
               plugins: [StatePlugin],
               routes: nil,
               metadata: nil
             )
  end

  test "keeps defaults and explicit nil values at the definition boundary" do
    expected = %Agent{
      id: nil,
      module: Agent,
      name: "defaults",
      description: nil,
      max_state_size: nil,
      schema: Zoi.object(%{}),
      plugins: [],
      state: nil,
      routes: [],
      metadata: %{}
    }

    assert {:ok, ^expected} = Agent.new(name: "defaults")

    assert {:ok, ^expected} =
             Agent.new(%{
               name: "defaults",
               id: nil,
               state: nil,
               description: nil,
               max_state_size: nil
             })

    for field <- [:name, :module, :schema, :plugins, :routes, :metadata] do
      assert {:error, %ValidationError{}} = Agent.new(Map.put(%{name: "defaults"}, field, nil))
    end
  end

  test "rejects unknown keys and instance data before common fields or callbacks" do
    attrs = %{name: nil, id: "instance", state: %{}, plugins: [CallbackPlugin]}

    assert {:error,
            %ValidationError{message: "Unknown Agent definition key", details: %{key: :extra}}} =
             Agent.new(Map.put(attrs, :extra, true))

    assert {:error,
            %ValidationError{
              message: "Agent.new/1 accepts definition data only",
              details: %{keys: [:id, :state]}
            }} = Agent.new(attrs)

    refute_received {:callback, _, _}
  end

  test "reports the first common field error when later fields also fail" do
    failures = [
      {:name, nil},
      {:description, 123},
      {:module, nil},
      {:max_state_size, -1},
      {:plugins, nil},
      {:schema, nil},
      {:routes, nil},
      {:metadata, nil}
    ]

    for index <- 0..(length(failures) - 1) do
      {field, value} = Enum.at(failures, index)

      assert {:error, %ValidationError{} = expected} =
               Agent.new(Map.put(%{name: "order"}, field, value))

      attrs = Map.merge(%{name: "order"}, Map.new(Enum.drop(failures, index)))
      assert {:error, %ValidationError{} = actual} = Agent.new(attrs)
      assert {actual.message, actual.details} == {expected.message, expected.details}
    end
  end

  test "calls Plugin schema callbacks twice in order before route and metadata checks" do
    opts = [label: :first]

    for extra <- [%{}, %{routes: nil}, %{metadata: nil}] do
      result =
        Agent.new(Map.merge(%{name: "callbacks", plugins: [{CallbackPlugin, opts}]}, extra))

      if extra == %{} do
        assert {:ok, %Agent{plugins: [{CallbackPlugin, ^opts}]}} = result
      else
        assert {:error, %ValidationError{}} = result
      end

      for callback <- [:state_spec, :directives, :state_spec, :directives] do
        assert_received {:callback, actual, ^opts}
        assert actual == callback
      end

      refute_received {:callback, _, _}
    end

    assert {:error, %ValidationError{}} =
             Agent.new(name: "callbacks", plugins: [CallbackPlugin], schema: nil)

    assert_received {:callback, :state_spec, []}
    assert_received {:callback, :directives, []}
    refute_received {:callback, _, _}
  end
end

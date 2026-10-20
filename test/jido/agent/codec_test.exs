defmodule Jido.Agent.CodecTest do
  use ExUnit.Case, async: true
  alias Jido.Agent
  alias Jido.Agent.Codec
  alias Jido.Authoring.Registry
  alias JidoTest.AgentFixtures.Add

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

  test "Codec rejects the old Agent envelope" do
    definition = Agent.define!(%{name: "new_document"})
    registry = registry(definition, nil)

    assert {:error, _error} =
             Codec.decode(%{"type" => "jido.agent", "version" => 1, "agent" => %{}}, registry)
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

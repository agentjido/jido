defmodule Jido.Agent.CodecTest do
  use ExUnit.Case, async: true
  alias Jido.Agent
  alias Jido.Agent.Codec
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

  test "Codec retains route defaults and a complete instance" do
    for defaults <- [%{}, %{by: 2}] do
      definition =
        Agent.define!(%{
          name: "defaults",
          routes: [
            %{path: "counter.add", handler: %{kind: :action, target: Add}, defaults: defaults}
          ]
        })

      for value <- [definition, Agent.instantiate!(definition, id: "encoded")] do
        assert {:ok, document, registry} = Codec.encode(value)
        assert {:ok, ^document} = Codec.encode(value, registry)
        assert {:ok, ^value} = Codec.decode(JSON.decode!(JSON.encode!(document)), registry)
      end

      [route] = definition.routes

      for invalid <- [false, 1, "invalid", [], {1, 2}, %URI{}] do
        assert {:error, %{path: [:routes, 0, :defaults]}} =
                 Codec.encode(%{definition | routes: [%{route | defaults: invalid}]})
      end
    end
  end

  test "Codec validates the current executable kind" do
    definition =
      Agent.define!(%{
        name: "changing_target",
        routes: [%{path: "counter.route", handler: %{kind: :action, target: ChangingTarget}}]
      })

    assert {:ok, _, registry} = Codec.encode(definition)
    Process.put({ChangingTarget, :kind}, :flow)

    for result <- [Codec.encode(definition), Codec.encode(definition, registry)] do
      assert {:error, %{code: :invalid_executable, path: [:routes, 0, :handler]}} = result
    end
  end
end

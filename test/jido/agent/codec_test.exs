defmodule Jido.Agent.CodecTest do
  use ExUnit.Case, async: true

  alias Jido.Agent
  alias Jido.Agent.Codec
  alias Jido.Codec.Data
  alias JidoTest.AgentFixtures.Add

  defmodule ChangingTarget do
    @behaviour Jido.Action

    def __jido_authoring_kind__, do: Process.get({__MODULE__, :kind}, :action)

    @impl true
    def validate_params(value), do: {:ok, value}
    @impl true
    def validate_output(value), do: {:ok, value}
    @impl true
    def run(_input, _context), do: raise("encoding must not execute Actions")
  end

  test "Codec round trips every accepted route defaults form" do
    for target <- [Add, {Add, %{}}, {Add, %{by: 2}}] do
      definition =
        Agent.new!(name: "defaults", routes: [{"counter.add", target, priority: 7}])

      assert {:ok, document, registry} = Codec.encode(definition)
      assert {:ok, ^document} = Codec.encode(definition, registry)
      assert {:ok, ^definition} = Codec.decode(JSON.decode!(JSON.encode!(document)), registry)
    end
  end

  test "Codec rejects defaults that are not plain maps" do
    definition =
      Agent.new!(
        name: "defaults",
        metadata: %{uri: %URI{port: 1}},
        routes: [{"counter.add", Add}]
      )

    {:ok, document, registry} = Codec.encode(definition)
    [route] = document["routes"]

    for defaults <- [false, 1, 1.0, "invalid", [], {1, 2}, %URI{port: 1}] do
      assert {:ok, encoded} = Data.encode(defaults, registry)
      invalid = %{document | "routes" => [%{route | "defaults" => encoded}]}

      assert {:error, %Jido.Error.ValidationError{message: "Route defaults must be a plain map"}} =
               Codec.decode(invalid, registry)
    end
  end

  test "Codec validates the current Instruction target contract" do
    definition =
      Agent.new!(name: "changing_target", routes: [{"counter.route", ChangingTarget}])

    assert {:ok, _document, registry} = Codec.encode(definition)

    Process.put({ChangingTarget, :kind}, :flow)

    for result <- [Codec.encode(definition), Codec.encode(definition, registry)] do
      assert {:error, %Jido.Error.ValidationError{} = error} = result
      assert error.message == "Invalid Agent route executable"
      assert error.details.target == ChangingTarget
      assert error.details.reason.details.reason == "missing flow/0"
    end
  end
end

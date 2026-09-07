defmodule Jido.Agent.CodecContractTest do
  use ExUnit.Case, async: true

  alias Jido.Agent
  alias Jido.Agent.Codec
  alias Jido.Agent.Codec.Data
  alias JidoTest.AgentFixtures.Add

  defmodule ChangingTarget do
    def __jido_executable__ do
      count = Process.get({__MODULE__, :count}, 0) + 1
      Process.put({__MODULE__, :count}, count)

      if count == Process.get({__MODULE__, :fail_at}) do
        case Process.get({__MODULE__, :failure}) do
          :invalid -> :invalid
          :raise -> raise "descriptor failed"
        end
      else
        Jido.Executable.action(__MODULE__)
      end
    end

    def validate_params(value), do: {:ok, value}
    def validate_output(value), do: {:ok, value}
    def run(_input, _context), do: raise("encoding must not execute Actions")
  end

  test "Codec round trips every accepted route defaults form" do
    for target <- [Add, {Add, %{}}, {Add, %{by: 2}}, {Add, %URI{port: 1}}] do
      definition =
        Agent.new!(name: "defaults", routes: [{"counter.add", target, priority: 7}])

      assert {:ok, document, registry} = Codec.encode(definition)
      assert {:ok, ^document} = Codec.encode(definition, registry)
      assert {:ok, ^definition} = Codec.decode(JSON.decode!(JSON.encode!(document)), registry)
    end
  end

  test "Codec still rejects non-map route defaults" do
    definition = Agent.new!(name: "defaults", routes: [{"counter.add", Add}])
    {:ok, document, registry} = Codec.encode(definition)
    [route] = document["routes"]

    for defaults <- [false, 1, 1.0, "invalid", [], {1, 2}] do
      assert {:ok, encoded} = Data.encode(defaults, registry)
      invalid = %{document | "routes" => [%{route | "defaults" => encoded}]}

      assert {:error, %Jido.Error.ValidationError{message: "Route defaults must be a plain map"}} =
               Codec.decode(invalid, registry)
    end
  end

  test "generated Codec returns descriptor errors and stops at the first failed route" do
    for index <- 1..3, failure <- [:invalid, :raise] do
      Process.delete({ChangingTarget, :fail_at})

      definition =
        Agent.new!(
          name: "changing_target",
          routes: for(n <- 1..3, do: {"counter.route#{n}", ChangingTarget})
        )

      Process.put({ChangingTarget, :count}, 0)
      Process.put({ChangingTarget, :fail_at}, 3 + index)
      Process.put({ChangingTarget, :failure}, failure)

      assert {:error, %Jido.Action.Error.ConfigurationError{} = error} = Codec.encode(definition)
      assert error.message == "invalid executable descriptor"
      assert error.details.executable == ChangingTarget

      assert error.details.reason ==
               if(failure == :invalid, do: :invalid_descriptor, else: :descriptor_callback_failed)

      assert Process.get({ChangingTarget, :count}) == 3 + index
    end
  end
end

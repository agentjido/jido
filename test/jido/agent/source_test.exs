defmodule Jido.Agent.SourceTest do
  use ExUnit.Case, async: true

  alias Jido.Agent.Source

  defmodule BrokenConfig do
    def __agent_config__, do: raise(ArgumentError, "configuration failed")
  end

  defmodule ThrownConfig do
    def __agent_config__, do: throw(:configuration_failed)
  end

  defmodule ExitedConfig do
    def __agent_config__, do: exit(:configuration_failed)
  end

  defmodule InvalidConfig do
    def __agent_config__, do: nil
  end

  test "definition and instance resolution preserve configuration exceptions" do
    for resolve <- [&Source.definition/1, &Jido.Agent.instantiate(&1, [])] do
      assert {:error, error} = resolve.(BrokenConfig)
      assert error.message == "Agent module configuration failed"

      assert error.details == %{
               module: BrokenConfig,
               kind: :error,
               reason: %ArgumentError{message: "configuration failed"}
             }
    end
  end

  test "configuration throws and exits remain structured errors with their causes" do
    for {module, kind} <- [{ThrownConfig, :throw}, {ExitedConfig, :exit}] do
      assert {:error, error} = Source.definition(module)
      assert error.details == %{module: module, kind: kind, reason: :configuration_failed}
    end
  end

  test "invalid configuration retains its validation error" do
    assert {:error, expected} = Jido.Agent.new(nil)
    assert {:error, error} = Source.definition(InvalidConfig)
    assert error.message == expected.message
  end

  test "Topology adds the declaration path without replacing the configuration cause" do
    assert {:error, error} =
             Jido.Topology.new(name: "broken", agents: [%{key: :worker, module: BrokenConfig}])

    assert error.details.source_path == [:agents, 0, :module]
    assert error.details.reason == %ArgumentError{message: "configuration failed"}
  end
end

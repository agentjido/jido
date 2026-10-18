defmodule Jido.Agent.ValidationResolutionTest do
  use ExUnit.Case, async: true

  alias Jido.Agent.Validation

  defmodule BrokenConfig do
    def definition, do: raise(ArgumentError, "configuration failed")
  end

  defmodule ThrownConfig do
    def definition, do: throw(:configuration_failed)
  end

  defmodule ExitedConfig do
    def definition, do: exit(:configuration_failed)
  end

  defmodule InvalidConfig do
    def definition, do: nil
  end

  test "definition and instance resolution preserve configuration exceptions" do
    for resolve <- [&Validation.resolve/1, &Jido.Agent.instantiate(&1, [])] do
      assert {:error, error} = resolve.(BrokenConfig)
      assert error.message == "Agent module definition failed"

      assert error.details == %{
               module: BrokenConfig,
               kind: :error,
               reason: %ArgumentError{message: "configuration failed"}
             }
    end
  end

  test "configuration throws and exits remain structured errors with their causes" do
    for {module, kind} <- [{ThrownConfig, :throw}, {ExitedConfig, :exit}] do
      assert {:error, error} = Validation.resolve(module)
      assert error.details == %{module: module, kind: kind, reason: :configuration_failed}
    end
  end

  test "invalid configuration retains its validation error" do
    assert {:error, error} = Validation.resolve(InvalidConfig)
    assert error.code == :definition_required
  end
end

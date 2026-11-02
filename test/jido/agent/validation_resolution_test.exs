defmodule Jido.Agent.ValidationResolutionTest do
  use Covenant.Case, component: "jido.agent", async: true

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

  @tag obligation: "jido.agent.I22"
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

  @tag obligation: "jido.agent.I22"
  test "configuration throws and exits remain structured errors with their causes" do
    for {module, kind} <- [{ThrownConfig, :throw}, {ExitedConfig, :exit}] do
      assert {:error, error} = Validation.resolve(module)
      assert error.details == %{module: module, kind: kind, reason: :configuration_failed}
    end
  end

  @tag obligation: "jido.agent.I22"
  test "invalid configuration retains its validation error" do
    assert {:error, error} = Validation.resolve(InvalidConfig)
    assert error.code == :definition_required
  end

  @tag obligation: "jido.agent.I22"
  test "loaded Agent module detection requires the definition callback" do
    assert Validation.loaded_agent_module?(BrokenConfig) === true
    assert Validation.loaded_agent_module?(String) === false
  end

  @tag obligation: "jido.agent.I22"
  test "resolution separates invalid values from unavailable modules" do
    for value <- [nil, true, false, "module"] do
      assert {:error,
              %Jido.Agent.Error{
                code: :definition_required,
                message: message,
                details: %{}
              }} = Validation.resolve(value)

      assert message != ""
    end

    missing = Module.concat(__MODULE__, Missing)

    assert {:error,
            %Jido.Agent.Error{
              code: :unresolved_definition,
              message: message,
              details: %{module: ^missing}
            }} = Validation.resolve(missing)

    assert message != ""
  end
end

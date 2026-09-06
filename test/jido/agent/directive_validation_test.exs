defmodule Jido.Agent.DirectiveValidationTest do
  use JidoTest.Case, async: true
  alias Jido.Agent.Directive

  test "built-in validation checks Error, Spawn and child adoption fields" do
    for directive <- [
          Directive.error(:failed, :action),
          Directive.spawn({Elixir.Agent, fn -> 0 end}),
          Directive.adopt_child(self(), :child)
        ] do
      assert Directive.built_in?(directive)
      assert {:ok, ^directive} = Directive.validate(directive)
    end

    refute Directive.built_in?(:unknown)

    assert {:error, %Jido.Error.ValidationError{message: "Unknown Agent Directive"}} =
             Directive.validate(:unknown)
  end

  test "child start validation rejects unsupported lifecycle options and malformed targets" do
    assert :ok = Directive.validate_restart_policy(:temporary)
    assert {:error, message} = Directive.validate_restart_policy(:invalid)
    assert message =~ "restart must be one of"
    assert :ok = Directive.validate_spawn_agent_opts(%{id: "child"})

    assert {:error, message} =
             Directive.validate_spawn_agent_opts(%{restore: :required, persistence: :invalid})

    assert message =~ "does not support lifecycle options"
    assert {:error, message} = Directive.validate_spawn_agent_opts([])
    assert message =~ "opts must be a map"
    assert {:error, {:invalid_agent, 42}} = Directive.validate_agent_target(42)
    agent = JidoTest.AgentFixtures.CounterAgent.new!()
    invalid = %{agent | state: %{count: :invalid, history: []}}
    assert {:error, _} = Directive.validate_agent_target(invalid)
    assert {:error, _} = Directive.validate(Directive.spawn_agent(invalid, :child))
  end
end

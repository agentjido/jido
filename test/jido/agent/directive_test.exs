defmodule Jido.Agent.DirectiveTest do
  use ExUnit.Case, async: true
  alias Jido.Agent.Directive
  alias Jido.Signal

  defmodule PlainDirective do
    use Jido.Agent.Directive
    defstruct [:value]
  end

  defmodule SchemaDirective do
    use Jido.Agent.Directive

    @schema Zoi.struct(__MODULE__, %{value: Zoi.integer()}, coerce: true)
    defstruct [:value]
    def schema, do: @schema
  end

  defmodule OverrideDirective do
    use Jido.Agent.Directive
    defstruct [:value]

    @impl true
    def validate(%__MODULE__{}), do: {:error, :custom_validation}
    def validate(_value), do: {:error, :wrong_type}
  end

  test "custom Directives can use the behavior before their struct is defined" do
    plain = %PlainDirective{value: 1}
    assert {:ok, ^plain} = PlainDirective.validate(plain)
    assert {:ok, ^plain} = Directive.validate(plain)

    typed = %SchemaDirective{value: 1}
    assert {:ok, ^typed} = SchemaDirective.validate(typed)
    assert {:ok, ^typed} = Directive.validate(typed)
    assert {:error, _issues} = SchemaDirective.validate(%SchemaDirective{value: "invalid"})

    for module <- [PlainDirective, SchemaDirective],
        value <- [:invalid, %URI{}, plain, typed],
        not is_struct(value, module) do
      assert {:error, %Jido.Error.ValidationError{}} = module.validate(value)
    end
  end

  test "custom Directives can override the default validator" do
    assert {:error, :custom_validation} = Directive.validate(%OverrideDirective{value: 1})
    assert {:error, :wrong_type} = OverrideDirective.validate(:invalid)
  end

  test "built-in validation checks Error, SpawnProcess and child adoption fields" do
    process = Directive.spawn_process({Elixir.Agent, fn -> 0 end})
    refute Map.has_key?(process, :tag)

    for directive <- [
          Directive.error(:failed, :action),
          process,
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
    assert :ok = Directive.validate_spawn_child_opts(%{id: "child"})

    assert {:error, message} =
             Directive.validate_spawn_child_opts(%{restore: :required, persistence: :invalid})

    assert message =~ "does not support lifecycle options"
    assert {:error, message} = Directive.validate_spawn_child_opts([])
    assert message =~ "opts must be a map"
    assert {:error, {:invalid_agent, 42}} = Directive.validate_agent_target(42)
    agent = JidoTest.AgentFixtures.CounterAgent.new!()
    invalid = %{agent | state: %{count: :invalid, history: []}}
    assert {:error, _} = Directive.validate_agent_target(invalid)
    assert {:error, _} = Directive.validate(Directive.spawn_child(invalid, :child))
  end

  test "Signal Directives validate the complete outbound envelope" do
    signal = Signal.new!("agent.outbound", %{value: 1}, source: "/agent")

    for malformed <- [
          %{signal | id: ""},
          %{signal | source: ""},
          %{signal | type: ""},
          %{signal | specversion: "2.0"},
          %{signal | extensions: %URI{host: "example.com"}},
          %{signal | extensions: %{"Bad_Key" => "value"}},
          %{signal | extensions: %{"invalid" => self()}}
        ],
        directive <- [
          Directive.emit(malformed),
          Directive.emit_to_parent(malformed),
          Directive.emit_to_child(:child, malformed)
        ] do
      assert {:error, _reason} = Directive.validate(directive)
    end

    for directive <- [
          Directive.emit(signal),
          Directive.emit_to_parent(signal),
          Directive.emit_to_child(:child, signal)
        ] do
      assert {:ok, ^directive} = Directive.validate(directive)
    end
  end
end

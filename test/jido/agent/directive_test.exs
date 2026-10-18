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

  test "built-in validation checks runtime error and process requests" do
    process = Jido.AgentServer.Directive.process_start({Elixir.Agent, fn -> 0 end})
    refute Map.has_key?(process, :tag)

    for directive <- [
          Jido.AgentServer.Directive.error_report(:failed, :action),
          process
        ] do
      assert Directive.built_in?(directive)
      assert {:ok, ^directive} = Directive.validate(directive)
    end

    refute Directive.built_in?(:unknown)

    assert {:error, %Jido.Error.ValidationError{message: "Unknown Agent Directive"}} =
             Directive.validate(:unknown)
  end

  test "child start validation rejects unsupported lifecycle options and malformed targets" do
    assert :ok = Jido.AgentServer.Directive.validate_restart_policy(:temporary)
    assert {:error, message} = Jido.AgentServer.Directive.validate_restart_policy(:invalid)
    assert message =~ "restart must be one of"
    assert :ok = Jido.AgentServer.Directive.validate_agent_start_opts(%{id: "child"})

    assert {:error, message} =
             Jido.AgentServer.Directive.validate_agent_start_opts(%{
               restore: :required,
               persistence: :invalid
             })

    assert message =~ "does not support lifecycle options"
    assert {:error, message} = Jido.AgentServer.Directive.validate_agent_start_opts([])
    assert message =~ "opts must be a map"
    assert {:error, {:invalid_agent, 42}} = Jido.AgentServer.Directive.validate_agent_target(42)
    agent = JidoTest.AgentFixtures.CounterAgent.instantiate!(id: "invalid-target")
    invalid = %{agent | state: %{count: :invalid, history: []}}
    assert {:error, _} = Jido.AgentServer.Directive.validate_agent_target(invalid)

    assert {:error, _} =
             Directive.validate(Jido.AgentServer.Directive.agent_start(invalid, :child))
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
          Jido.AgentServer.Directive.owner_send(malformed),
          Jido.AgentServer.Directive.agent_send(:child, malformed)
        ] do
      assert {:error, _reason} = Directive.validate(directive)
    end

    for directive <- [
          Directive.emit(signal),
          Jido.AgentServer.Directive.owner_send(signal),
          Jido.AgentServer.Directive.agent_send(:child, signal)
        ] do
      assert {:ok, ^directive} = Directive.validate(directive)
    end
  end

  test "child helpers reject option typos and ambiguous or malformed containers" do
    for opts <- [
          [restat: :permanent],
          [restart: :permanent, restart: :temporary],
          [opts: [id: "first", id: "second"]],
          [meta: [role: :first, role: :second]],
          [opts: %URI{}],
          [meta: :invalid],
          [{"restart", :permanent}],
          [:invalid],
          %{restart: :permanent}
        ] do
      assert_raise ArgumentError, fn ->
        Jido.AgentServer.Directive.agent_start(JidoTest.AgentFixtures.CounterAgent, :child, opts)
      end
    end
  end

  test "child helpers retain supported options with maps or keyword lists" do
    for {opts, meta} <- [
          {%{id: "child"}, %{role: :worker}},
          {[id: "child"], [role: :worker]}
        ] do
      directive =
        Jido.AgentServer.Directive.agent_start(JidoTest.AgentFixtures.CounterAgent, :child,
          node: node(),
          opts: opts,
          meta: meta,
          restart: :temporary
        )

      assert directive.opts == %{id: "child"}
      assert directive.meta == %{role: :worker}
      assert directive.node == node()
      assert directive.restart == :temporary
      assert {:ok, ^directive} = Directive.validate(directive)
    end
  end
end

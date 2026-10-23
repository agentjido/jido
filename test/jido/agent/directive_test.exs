defmodule Jido.Agent.DirectiveContractTest do
  use Covenant.Case, component: "jido.agent", async: true
  alias Jido.Agent.Directive
  alias Jido.AgentServer.Directive, as: Runtime
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

  defmodule ChangedType do
    use Jido.Agent.Directive
    defstruct []
    def validate(%__MODULE__{}), do: {:ok, %PlainDirective{}}
  end

  defmodule InvalidResult do
    use Jido.Agent.Directive
    defstruct []
    def validate(%__MODULE__{}), do: :invalid
  end

  defmodule Raises do
    use Jido.Agent.Directive
    defstruct []
    def validate(%__MODULE__{}), do: raise("validation fault")
  end

  defmodule Throws do
    use Jido.Agent.Directive
    defstruct []
    def validate(%__MODULE__{}), do: throw(:validation_fault)
  end

  defmodule SignalField do
    use Jido.Agent.Directive
    defstruct [:signal]
  end

  @tag obligation: "jido.agent.I27"
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

  @tag obligation: "jido.agent.I27"
  test "custom Directives can override the default validator" do
    assert {:error, :custom_validation} = Directive.validate(%OverrideDirective{value: 1})
    assert {:error, :wrong_type} = OverrideDirective.validate(:invalid)
  end

  @tag obligation: "jido.agent.I27"
  test "built-in identity and validation cover runtime and definition Directives" do
    signal = Signal.new!("event", %{}, source: "/test")
    request = Signal.new!("request", %{}, source: "/test")
    reply = Signal.new!("response", %{value: 1}, source: "/test")
    {:ok, reply} = Signal.put_context(reply, "jidocausationid", request.id)

    directives = [
      Directive.emit(signal),
      Directive.reply(reply),
      Runtime.parent_send(signal),
      Runtime.agent_send(:child, signal),
      Runtime.agent_start(JidoTest.AgentFixtures.CounterAgent, :child),
      Runtime.agent_stop(:child),
      Runtime.error_report(:failed, :action),
      Runtime.process_start({Elixir.Agent, fn -> 0 end}),
      Runtime.server_stop(),
      Directive.agent_add(:child, JidoTest.AgentFixtures.CounterAgent),
      Directive.agent_remove(:child),
      Directive.route_add("event", JidoTest.AgentContract.Add,
        state: %{source: :output, path: []}
      ),
      Directive.route_remove("event"),
      Directive.connection_add("event", from: :root, to: :child),
      Directive.connection_remove("event", from: :root, to: :child),
      Directive.plugin_add(JidoTest.AgentContract.Stateless)
    ]

    for directive <- directives do
      assert Directive.built_in?(directive) === true
      assert Directive.built_in_module?(directive.__struct__) === true
      assert Directive.validator?(directive.__struct__) === true
      assert {:ok, ^directive} = Directive.validate(directive)
    end

    assert Directive.built_in?(:unknown) === false
    assert Directive.built_in?(%PlainDirective{}) === false
    assert Directive.validator?(PlainDirective) === true

    assert {:error, %Jido.Error.ValidationError{details: %{directive: :unknown}}} =
             Directive.validate(:unknown)
  end

  @tag obligation: "jido.agent.I27"
  test "Signal Directives require and normalize one complete Signal" do
    signal = Signal.new!("agent.outbound", %{value: 1}, source: "/agent")
    {:ok, reply} = Signal.put_context(signal, "jidocausationid", "request-id")

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
          Runtime.parent_send(malformed),
          Runtime.agent_send(:child, malformed)
        ] do
      assert {:error, _reason} = Directive.validate(directive)
    end

    for directive <- [
          Directive.emit(signal),
          Runtime.parent_send(signal),
          Runtime.agent_send(:child, signal)
        ] do
      assert {:ok, ^directive} = Directive.validate(directive)
    end

    assert {:ok, %Directive.Reply{signal: ^reply}} =
             reply |> Directive.reply() |> Directive.validate()

    assert {:error, %Jido.Error.ValidationError{}} =
             signal |> Directive.reply() |> Directive.validate()

    for directive <- [
          %Directive.Emit{signal: %{}},
          %Directive.Reply{signal: %{}},
          %{Runtime.parent_send(signal) | signal: %{}},
          %{Runtime.agent_send(:child, signal) | signal: %{}}
        ] do
      assert {:error, %Jido.Error.ValidationError{details: %{directive: ^directive}}} =
               Directive.validate(directive)
    end
  end

  @tag obligation: "jido.agent.I27"
  test "AgentServer validates Reply against the current requester" do
    signal = Signal.new!("response", %{}, source: "/test")
    {:ok, signal} = Signal.put_context(signal, "jidocausationid", "request-id")

    config = %{
      directive_handler: fn _directive, _context -> :ok end,
      max_directives_per_turn: 10
    }

    assert {:error, :requester_not_found} =
             Jido.AgentServer.Effects.validate_batch([Directive.reply(signal)], config)

    assert :ok =
             Jido.AgentServer.Effects.validate_batch(
               [Directive.reply(signal)],
               Map.put(config, :requester, self())
             )
  end

  @tag obligation: "jido.agent.I27"
  test "custom Directive validation contains changed types, invalid results, and faults" do
    custom = %SignalField{signal: Signal.new!("event", %{}, source: "/test")}
    assert {:ok, ^custom} = Directive.validate(custom)

    assert {:error,
            %Jido.Error.ValidationError{
              details: %{expected: ChangedType, actual: PlainDirective}
            }} = Directive.validate(%ChangedType{})

    assert {:error,
            %Jido.Error.ValidationError{
              details: %{directive: InvalidResult, result: :invalid}
            }} = Directive.validate(%InvalidResult{})

    assert {:error,
            %Jido.Error.ExecutionError{
              details: %{directive: Raises, error: %RuntimeError{message: "validation fault"}}
            }} = Directive.validate(%Raises{})

    assert {:error,
            %Jido.Error.ExecutionError{
              details: %{directive: Throws, kind: :throw, reason: :validation_fault}
            }} = Directive.validate(%Throws{})
  end

  @tag obligation: ["jido.agent.I27", "jido.agent.I29"]
  test "Directive constructors preserve every supported option and explicit nil" do
    signal = Signal.new!("event", %{}, source: "/test")
    {:ok, reply} = Signal.put_context(signal, "jidocausationid", "request-id")
    assert Directive.emit("event", %{}) === %{kind: :emit, type: "event", data: %{}}

    assert Directive.emit(signal, :dispatch) === %Directive.Emit{
             signal: signal,
             dispatch: :dispatch
           }

    assert Directive.reply(reply) === %Directive.Reply{signal: reply}

    assert {:error, _} = Directive.emit("event.*", %{})
    assert {:error, _} = Directive.emit("event", [])

    assert %{count: 2, initial_state: %{count: 1}} =
             Directive.agent_add(:child, JidoTest.AgentFixtures.CounterAgent,
               count: 2,
               initial_state: %{count: 1}
             )

    assert %{count: 3, initial_state: %{count: 2}} =
             Directive.agent_replace(:child, JidoTest.AgentFixtures.CounterAgent,
               count: 3,
               initial_state: %{count: 2}
             )

    assert %{as: :run, defaults: %{amount: 1}} =
             Directive.route_add("run", JidoTest.AgentContract.Add,
               as: :run,
               defaults: %{amount: 1}
             )

    assert %{as: :next, defaults: %{amount: 2}} =
             Directive.route_replace("run", JidoTest.AgentContract.Add,
               as: :next,
               defaults: %{amount: 2}
             )

    assert %{from: :root, to: :child} =
             Directive.connection_remove("run", from: :root, to: :child)

    assert %{delivery: :broadcast} =
             Directive.connection_replace("run",
               from: :root,
               to: :child,
               delivery: :broadcast
             )

    assert %{options: [start: 1], initial: :default} =
             Directive.plugin_add(JidoTest.AgentContract.First, start: 1)

    assert %{options: [], initial: {:value, nil}} =
             Directive.plugin_add(JidoTest.AgentContract.First, [], initial: nil)

    assert_raise ArgumentError, fn ->
      Directive.plugin_add(JidoTest.AgentContract.First, [], initial: 1, initial: 2)
    end
  end
end

defmodule Jido.AgentServer.DirectiveTest do
  use ExUnit.Case, async: true

  alias Jido.Agent.Directive

  test "child start validation rejects unsupported lifecycle options and malformed targets" do
    assert :ok = Jido.AgentServer.Directive.validate_restart_policy(:temporary)
    assert {:error, message} = Jido.AgentServer.Directive.validate_restart_policy(:invalid)
    assert message =~ "restart must be one of"
    assert :ok = Jido.AgentServer.Directive.validate_agent_start_opts(%{id: "child"})

    assert {:error, "AgentStart does not support initialization input"} =
             Jido.AgentServer.Directive.validate_agent_start_opts(%{input: %{}})

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

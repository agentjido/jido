defmodule Jido.Agent.DirectiveContractTest do
  use Covenant.Case, component: "jido.agent", async: true
  alias Jido.Agent.Directive
  alias Jido.Agent.Directive.Kind
  alias Jido.Signal

  defmodule PlainDirective do
    use Jido.Agent.Directive
    defstruct [:value]
  end

  defmodule SchemaDirective do
    use Jido.Agent.Directive

    @schema Jido.Joi.struct(__MODULE__, %{value: Jido.Joi.integer()}, coerce: true)
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
  test "built-in identity and validation cover runtime Directives" do
    signal = Signal.new!("event", %{}, source: "/test")
    request = Signal.new!("request", %{}, source: "/test")
    reply = Signal.new!("response", %{value: 1}, source: "/test")
    {:ok, reply} = Signal.put_context(reply, "jidocausationid", request.id)

    directives = [
      Directive.emit(signal),
      Directive.reply(reply)
    ]

    for directive <- directives do
      assert Kind.built_in?(directive) === true
      assert Kind.built_in_module?(directive.__struct__) === true
      assert Kind.validator?(directive.__struct__) === true
      assert {:ok, ^directive} = Directive.validate(directive)
    end

    assert Kind.built_in?(:unknown) === false
    assert Kind.built_in?(%PlainDirective{}) === false
    assert Kind.validator?(PlainDirective) === true

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
          Directive.emit(malformed)
        ] do
      assert {:error, _reason} = Directive.validate(directive)
    end

    for directive <- [Directive.emit(signal)] do
      assert {:ok, ^directive} = Directive.validate(directive)
    end

    assert {:ok, %Directive.Reply{signal: ^reply}} =
             reply |> Directive.reply() |> Directive.validate()

    assert {:error, %Jido.Error.ValidationError{}} =
             signal |> Directive.reply() |> Directive.validate()

    for directive <- [
          %Directive.Emit{signal: %{}},
          %Directive.Reply{signal: %{}}
        ] do
      assert {:error, %Jido.Error.ValidationError{details: %{directive: ^directive}}} =
               Directive.validate(directive)
    end
  end

  @tag obligation: "jido.agent.I27"
  test "AgentServer validates Reply independently of the current requester" do
    signal = Signal.new!("response", %{}, source: "/test")
    {:ok, signal} = Signal.put_context(signal, "jidocausationid", "request-id")

    config = %{
      directive_handler: fn _directive, _context -> :ok end,
      max_directives_per_turn: 10
    }

    assert :ok = Jido.AgentServer.Effects.validate_batch([Directive.reply(signal)], config)

    assert :ok =
             Jido.AgentServer.Effects.validate_batch(
               [Directive.reply(signal)],
               Map.put(config, :requester, self())
             )

    assert :ok =
             Jido.AgentServer.Effects.validate_batch(
               [Directive.reply(signal)],
               Map.merge(config, %{durable: true, requester: nil})
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

  @tag obligation: "jido.agent.I27"
  test "Directive constructors preserve runtime values" do
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
  end
end

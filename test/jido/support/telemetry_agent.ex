defmodule JidoTest.TelemetryAgent.Deliver do
  @moduledoc false

  @schema Zoi.struct(__MODULE__, %{value: Zoi.integer()})
  @enforce_keys Zoi.Struct.enforce_keys(@schema)
  defstruct Zoi.Struct.struct_fields(@schema)

  def schema, do: @schema
  def validate(%__MODULE__{} = directive), do: Zoi.parse(@schema, directive)
end

defmodule JidoTest.TelemetryAgent.Output do
  @moduledoc false

  use Jido.Plugin, agent: __MODULE__.Agent, agent_server: __MODULE__.Server
end

defmodule JidoTest.TelemetryAgent.Output.Agent do
  use Jido.Agent.Plugin

  alias JidoTest.TelemetryAgent.Deliver

  @impl true
  def directives(_opts), do: [Deliver]
end

defmodule JidoTest.TelemetryAgent.Output.Server do
  use Jido.AgentServer.Plugin
  alias JidoTest.TelemetryAgent.Deliver

  @impl true
  def dispatch(nil, %Deliver{value: value}, context, _opts) do
    deliver = Map.get(context.turn_context, :deliver, fn _value -> :ok end)
    deliver.(value)
  end
end

defmodule JidoTest.TelemetryAgent do
  @moduledoc false

  use Jido.Agent, name: "test_telemetry_agent"

  agent do
    plugin __MODULE__.Output

    schema Zoi.object(%{
             value: Zoi.integer() |> Zoi.default(0),
             secret: Zoi.string() |> Zoi.default("private-agent-state")
           })
  end

  routes do
    signal_source "/test/telemetry"

    route "test.telemetry.record" do
      action %{value: value}, schema: Zoi.object(%{value: Zoi.integer()}), context: context do
        {:ok, %{context.agent_state | value: value}}
      end

      define :record, args: [:value]
    end

    route "test.telemetry.fail" do
      action _input, schema: Zoi.object(%{}), context: context do
        {:error, Map.get(context, :failure, :requested_execution_failure)}
      end

      define :fail_execution
    end

    route "test.telemetry.hold" do
      action %{value: value},
        schema: Zoi.object(%{value: Zoi.integer()}),
        context: context do
        context.barrier.()
        {:ok, %{context.agent_state | value: value}}
      end

      define :hold, args: [:value]
    end

    route "test.telemetry.missing_child" do
      action %{value: value},
        schema: Zoi.object(%{value: Zoi.integer()}),
        context: context do
        signal = Jido.Signal.new!("test.telemetry.deliver", %{value: value}, source: "/test")
        directive = Jido.Agent.Directive.emit_to_child(:missing, signal)
        {:ok, %{context.agent_state | value: value}, [directive]}
      end

      define :send_to_missing_child, args: [:value]
    end

    route "test.telemetry.deliver" do
      action %{value: value},
        schema: Zoi.object(%{value: Zoi.integer()}),
        context: context do
        effect = %JidoTest.TelemetryAgent.Deliver{value: value}
        {:ok, %{context.agent_state | value: value}, [effect]}
      end

      define :record_and_deliver, args: [:value]
    end
  end
end

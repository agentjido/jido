defmodule Jido.Examples.TurnObservation.Deliver do
  @moduledoc false
  @schema Zoi.struct(__MODULE__, %{value: Zoi.integer()})
  @enforce_keys Zoi.Struct.enforce_keys(@schema)
  defstruct Zoi.Struct.struct_fields(@schema)
  def schema, do: @schema
end

defmodule Jido.Examples.TurnObservation.Output do
  @moduledoc "A stateless output Plugin with a caller-supplied delivery function."
  use Jido.Plugin
  alias Jido.Examples.TurnObservation.Deliver

  @impl true
  def directives(_opts), do: [Deliver]

  @impl true
  def validate_directive(directive, _opts), do: Zoi.parse(Deliver.schema(), directive)

  @impl true
  def dispatch(nil, %Deliver{value: value}, context, _opts) do
    deliver = Map.get(context.turn_context, :deliver, fn _value -> :ok end)
    deliver.(value)
  end
end

defmodule Jido.Examples.TurnObservation do
  @moduledoc """
  OBS-01 probe inputs for success, validation, execution, cancellation, and
  post-commit failure. Commands use real Actions and the Agent Server.

  This Agent emits no application telemetry. The external collector must see
  SDK events. The Hold Action accepts a timing barrier through caller context.
  """
  use Jido.Agent, name: "example_turn_observation"

  agent do
    plugin __MODULE__.Output

    schema Zoi.object(%{
             value: Zoi.integer() |> Zoi.default(0),
             secret: Zoi.string() |> Zoi.default("private-agent-state")
           })
  end

  routes do
    signal_source "/examples/observation"

    route "observation.record" do
      action %{value: value},
        name: "observation_record",
        schema: Zoi.object(%{value: Zoi.integer()}),
        context: context do
        {:ok, %{context.agent_state | value: value}}
      end

      define :record, args: [:value]
    end

    route "observation.fail" do
      action _input, name: "observation_fail", schema: Zoi.object(%{}), context: context do
        {:error, Map.get(context, :failure, :requested_execution_failure)}
      end

      define :fail_execution
    end

    route "observation.hold" do
      action %{value: value},
        name: "observation_hold",
        schema: Zoi.object(%{value: Zoi.integer()}),
        context: context do
        context.barrier.()
        {:ok, %{context.agent_state | value: value}}
      end

      define :hold, args: [:value]
    end

    route "observation.missing_child" do
      action %{value: value},
        name: "observation_missing_child",
        schema: Zoi.object(%{value: Zoi.integer()}),
        context: context do
        signal =
          Jido.Signal.new!("observation.deliver", %{value: value},
            source: "/examples/observation"
          )

        directive = Jido.Agent.Directive.emit_to_child(:missing, signal)
        {:ok, %{context.agent_state | value: value}, [directive]}
      end

      define :send_to_missing_child, args: [:value]
    end

    route "observation.deliver" do
      action %{value: value},
        name: "observation_record_deliver",
        schema: Zoi.object(%{value: Zoi.integer()}),
        context: context do
        effect = %Jido.Examples.TurnObservation.Deliver{value: value}
        {:ok, %{context.agent_state | value: value}, [effect]}
      end

      define :record_and_deliver, args: [:value]
    end
  end
end

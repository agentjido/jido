defmodule Jido.Examples.Signals.SignalJourney.Correlation do
  @moduledoc "Copies one application correlation ID to outbound Signals."
  use Jido.Plugin

  alias Jido.Signal.Context

  @impl true
  def prepare_outbound(_runtime, signal, context, _opts) do
    case Context.get(context.source_signal, "jidocorrelationid") do
      correlation_id when is_binary(correlation_id) ->
        Context.put(signal, "jidocorrelationid", correlation_id)

      nil ->
        {:ok, signal}
    end
  end
end

defmodule Jido.Examples.Signals.SignalJourney.Coordinator do
  @moduledoc "Plans child work and owns canonical request completion state."

  use Jido.Agent,
    name: "signal_journey_coordinator",
    plugins: [Jido.Examples.Signals.SignalJourney.Correlation]

  state do
    schema(
      Jido.Joi.object(%{
        request_id: Jido.Joi.string() |> Jido.Joi.default(""),
        status: Jido.Joi.enum([:idle, :waiting, :completed]) |> Jido.Joi.default(:idle),
        result: Jido.Joi.integer() |> Jido.Joi.nullable() |> Jido.Joi.default(nil)
      })
    )
  end

  routes do
    signal_source "/examples/signals/journey/coordinator"

    route "examples.signals.journey.request", as: :request do
      action %{request_id: request_id, value: value, reply_to: reply_to},
        schema:
          Jido.Joi.object(%{
            request_id: Jido.Joi.string() |> Jido.Joi.min(1),
            value: Jido.Joi.integer(),
            reply_to: Jido.Joi.map()
          }),
        output_schema:
          Jido.Joi.object(%{
            state: Jido.Joi.map(),
            child: Jido.Joi.map()
          }),
        context: context do
        state = %{context.agent_state | request_id: request_id, status: :waiting, result: nil}
        {:ok, %{state: state, child: %{request_id: request_id, value: value, reply_to: reply_to}}}
      end

      state(from: output(:state))
      reply("examples.signals.journey.planned", from: output(:child))
    end

    route "examples.signals.journey.child.completed", as: :complete do
      action %{request_id: request_id, result: result},
        schema:
          Jido.Joi.object(%{
            request_id: Jido.Joi.string() |> Jido.Joi.min(1),
            result: Jido.Joi.integer(),
            reply_to: Jido.Joi.map(),
            duplicate: Jido.Joi.boolean()
          }),
        output_schema:
          Jido.Joi.object(%{
            state: Jido.Joi.map(),
            reply: Jido.Joi.map()
          }),
        context: context do
        state = %{context.agent_state | request_id: request_id, status: :completed, result: result}
        {:ok, %{state: state, reply: %{request_id: request_id, result: result}}}
      end

      state(from: output(:state))
      reply("examples.signals.journey.completed", from: output(:reply))
    end
  end
end

defmodule Jido.Examples.Signals.SignalJourney.Worker do
  @moduledoc "Runs idempotent child work under one stable logical identity."

  use Jido.Agent,
    name: "signal_journey_worker",
    plugins: [Jido.Examples.Signals.SignalJourney.Correlation]

  state do
    schema Jido.Joi.object(%{results: Jido.Joi.map() |> Jido.Joi.default(%{})})
  end

  routes do
    signal_source "/examples/signals/journey/worker"

    route "examples.signals.journey.child.request", as: :calculate do
      action %{request_id: request_id, value: value, reply_to: reply_to},
        schema:
          Jido.Joi.object(%{
            request_id: Jido.Joi.string() |> Jido.Joi.min(1),
            value: Jido.Joi.integer(),
            reply_to: Jido.Joi.map()
          }),
        output_schema:
          Jido.Joi.object(%{
            state: Jido.Joi.map(),
            reply: Jido.Joi.map()
          }),
        context: context do
        case Map.fetch(context.agent_state.results, request_id) do
          {:ok, result} ->
            {:ok,
             %{
               state: context.agent_state,
               reply: %{
                 request_id: request_id,
                 result: result,
                 reply_to: reply_to,
                 duplicate: true
               }
             }}

          :error ->
            result = value * 2
            state = put_in(context.agent_state, [:results, request_id], result)

            {:ok,
             %{
               state: state,
               reply: %{
                 request_id: request_id,
                 result: result,
                 reply_to: reply_to,
                 duplicate: false
               }
             }}
        end
      end

      state(from: output(:state))
      reply("examples.signals.journey.child.completed", from: output(:reply))
    end
  end
end

defmodule Jido.Examples.Signals.SignalJourney.FailOnceDelivery do
  @moduledoc "A local adapter that loses the first acknowledgement after acceptance."

  def start_link, do: Agent.start_link(fn -> 0 end)

  def deliver(adapter, operation) when is_function(operation, 0) do
    attempt = Agent.get_and_update(adapter, fn count -> {count + 1, count + 1} end)

    case {attempt, operation.()} do
      {1, {:ok, _accepted}} -> {:error, :acknowledgement_lost}
      {_attempt, result} -> result
    end
  end

  def attempts(adapter), do: Agent.get(adapter, & &1)
end

defmodule Jido.Examples.Signals.SignalJourney do
  @moduledoc "Runs one correlated request through coordinator and child Turns."

  alias Jido.Agent.Address
  alias Jido.Examples.Signals.SignalJourney.FailOnceDelivery
  alias Jido.Signal.Context
  alias Jido.Trace

  def run(instance, %Address{} = coordinator, %Address{} = worker, adapter, request_id, value) do
    request =
      Jido.Signal.new!(
        "examples.signals.journey.request",
        %{request_id: request_id, value: value, reply_to: Address.to_map!(coordinator)},
        source: "/examples/signals/journey/client"
      )

    {:ok, request} = Context.put_trace(request, Trace.new())
    {:ok, request} = Context.put(request, "jidocorrelationid", request_id)

    with {:ok, planned_turn} <- Jido.call(instance, coordinator, request),
         planned <- planned_turn.reply,
         {:ok, child} <- child_signal(planned),
         first <- FailOnceDelivery.deliver(adapter, fn -> Jido.call(instance, worker, child) end),
         {:error, :acknowledgement_lost} <- first,
         {:ok, child_turn} <- FailOnceDelivery.deliver(adapter, fn -> Jido.call(instance, worker, child) end),
         {:ok, completed_turn} <- Jido.call(instance, coordinator, child_turn.reply) do
      {:ok,
       %{
         request: request,
         planned: planned,
         child: child,
         child_reply: child_turn.reply,
         completed: completed_turn.reply,
         turns: %{planned: planned_turn, child: child_turn, completed: completed_turn},
         delivery_attempts: FailOnceDelivery.attempts(adapter),
         injected_failure: first
       }}
    end
  end

  defp child_signal(planned) do
    child =
      Jido.Signal.new!("examples.signals.journey.child.request", planned.data,
        source: "/examples/signals/journey/coordinator"
      )

    parent_trace = Context.get_trace(planned)

    with {:ok, child} <- Context.put_trace(child, Trace.child(parent_trace, causation_id: planned.id)),
         correlation_id when is_binary(correlation_id) <- Context.get(planned, "jidocorrelationid"),
         do: Context.put(child, "jidocorrelationid", correlation_id)
  end
end

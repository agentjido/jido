defmodule Jido.Examples.CausalTrace do
  @moduledoc """
  A parent sends work to two child Agents under one causal trace.

  The Agents return only business state and Directives. They do not add trace
  fields or emit application telemetry. The external EventProbe reads public
  SDK events for the parent and child Agent IDs.
  """

  use Jido.Agent, name: "example_causal_parent"

  state do
    schema Jido.Joi.object(%{
             request_id: Jido.Joi.string() |> Jido.Joi.default(""),
             results: Jido.Joi.map() |> Jido.Joi.default(%{}),
             private: Jido.Joi.string() |> Jido.Joi.default("private-causal-agent-state")
           })
  end

  routes do
    signal_source "/examples/runtime/causal_trace"

    route "examples.runtime.causal_trace.begin", as: :start_work do
      action input,
        schema:
          Jido.Joi.object(%{
            request_id: Jido.Joi.string() |> Jido.Joi.min(1),
            value: Jido.Joi.integer(),
            node: Jido.Joi.atom() |> Jido.Joi.optional()
          }),
        context: context do
        alias Jido.Agent.Directive, as: AgentDirective
        alias Jido.AgentServer.Directive
        alias Jido.Examples.CausalTrace.Worker

        if context.agent_state.request_id == "" do
          directives =
            Enum.flat_map([:left, :right], fn slot ->
              {:ok, command_signal_1} =
                Worker.compute_signal(%{
                  request_id: input.request_id,
                  slot: slot,
                  value: input.value
                })

              [
                Directive.agent_start(Worker, slot, node: input[:node], restart: :temporary),
                AgentDirective.agent_send(
                  slot,
                  command_signal_1
                )
              ]
            end)

          {:ok, %{context.agent_state | request_id: input.request_id}, directives}
        else
          {:error, :request_already_started}
        end
      end
    end

    route "examples.runtime.causal_trace.result", as: :collect_result do
      action input,
        schema:
          Jido.Joi.object(%{
            request_id: Jido.Joi.string(),
            slot: Jido.Joi.enum([:left, :right]),
            value: Jido.Joi.integer()
          }),
        context: context do
        if input.request_id == context.agent_state.request_id do
          {:ok,
           %{
             context.agent_state
             | results: Map.put(context.agent_state.results, input.slot, input.value)
           }}
        else
          {:error, :unrelated_result}
        end
      end
    end

    route "jido.agent.child.*", Jido.Examples.Support.KeepState
  end
end

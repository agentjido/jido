defmodule Jido.Examples.CausalTrace do
  @moduledoc """
  A parent sends work to two child Agents under one causal trace.

  The Agents return only business state and Directives. They do not add trace
  fields or emit application telemetry. The external EventProbe reads public
  SDK events for the parent and child Agent IDs.
  """

  use Jido.Agent, name: "example_causal_parent"

  agent do
    schema Zoi.object(%{
             request_id: Zoi.string() |> Zoi.default(""),
             results: Zoi.map() |> Zoi.default(%{}),
             private: Zoi.string() |> Zoi.default("private-causal-agent-state")
           })
  end

  routes do
    signal_source "/examples/runtime/causal_trace"

    route "examples.runtime.causal_trace.begin" do
      action input,
        schema:
          Zoi.object(%{
            request_id: Zoi.string() |> Zoi.min(1),
            value: Zoi.integer(),
            node: Zoi.atom() |> Zoi.optional()
          }),
        context: context do
        alias Jido.Agent.Directive
        alias Jido.Examples.CausalTrace.Worker

        if context.agent_state.request_id == "" do
          directives =
            Enum.flat_map([:left, :right], fn slot ->
              [
                Directive.spawn_agent(Worker, slot, node: input[:node], restart: :temporary),
                Directive.emit_to_child(
                  slot,
                  Worker.compute_signal!(input.request_id, slot, input.value)
                )
              ]
            end)

          {:ok, %{context.agent_state | request_id: input.request_id}, directives}
        else
          {:error, :request_already_started}
        end
      end

      define :start_work, args: [:request_id, :value]
    end

    route "examples.runtime.causal_trace.result" do
      action input,
        schema:
          Zoi.object(%{
            request_id: Zoi.string(),
            slot: Zoi.enum([:left, :right]),
            value: Zoi.integer()
          }),
        context: context do
        if input.request_id == context.agent_state.request_id do
          {:ok,
           %{context.agent_state | results: Map.put(context.agent_state.results, input.slot, input.value)}}
        else
          {:error, :unrelated_result}
        end
      end

      define :collect_result
    end

    route "jido.agent.child.*", Jido.Examples.Support.KeepState
  end
end

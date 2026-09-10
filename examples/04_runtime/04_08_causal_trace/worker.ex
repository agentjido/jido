defmodule Jido.Examples.CausalTrace.Worker do
  @moduledoc "A temporary child Agent that reports one computed value to its parent."

  use Jido.Agent, name: "example_causal_worker"

  agent do
    schema Zoi.object(%{value: Zoi.integer() |> Zoi.default(0)})
  end

  routes do
    signal_source "/examples/runtime/causal_trace"

    route "examples.runtime.causal_trace.compute" do
      action input,
        schema:
          Zoi.object(%{
            request_id: Zoi.string(),
            slot: Zoi.enum([:left, :right]),
            value: Zoi.integer()
          }),
        context: context do
        value = input.value * 2

        result =
          Jido.Examples.CausalTrace.collect_result_signal!(
            input: %{request_id: input.request_id, slot: input.slot, value: value}
          )

        {:ok, %{context.agent_state | value: value},
         [Jido.Agent.Directive.emit_to_parent(result)]}
      end

      define :compute, args: [:request_id, :slot, :value]
    end
  end
end

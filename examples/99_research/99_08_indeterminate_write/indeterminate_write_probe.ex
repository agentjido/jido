defmodule Jido.Examples.IndeterminateWriteProbe do
  @moduledoc """
  PERSIST-03: an uncertain persistence write must prevent further work on stale state.

  The stored candidate proves Action execution. The output Signal records
  post-commit dispatch. Its temporary destination stays in caller context.
  """
  use Jido.Agent, name: "research_indeterminate_write"

  agent do
    schema Zoi.object(%{count: Zoi.integer() |> Zoi.default(0)})
  end

  routes do
    signal_source "/examples/research/indeterminate_write"

    route "examples.research.indeterminate_write.increment" do
      action input,
        schema: Zoi.object(%{request_id: Zoi.string() |> Zoi.min(1), amount: Zoi.integer()}),
        context: context do
        next = %{context.agent_state | count: context.agent_state.count + input.amount}

        output =
          Jido.Signal.new!(
            "examples.research.indeterminate_write.applied",
            %{request_id: input.request_id, count: next.count},
            source: "/examples/research/indeterminate_write"
          )

        directives =
          if sink = context[:reply_to],
            do: [Jido.Agent.Directive.emit_to_pid(output, sink)],
            else: []

        {:ok, next, directives}
      end

      define :increment, args: [:request_id, :amount]
    end
  end
end

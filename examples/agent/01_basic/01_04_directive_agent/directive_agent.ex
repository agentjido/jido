defmodule Jido.Examples.DirectiveAgent do
  @moduledoc """
  An Agent that emits a batch of three recording Directives.

  The Effects Plugin records dispatch order and committed snapshots in a real
  supervised runtime. Invalid and failing batches test the commit boundary.
  """

  alias Jido.Examples.DirectiveAgent.{Effects, Record}

  use Jido.Agent, name: "basic_sdk_directives", plugins: [Effects]

  state do
    schema Jido.Joi.object(%{count: Jido.Joi.integer() |> Jido.Joi.default(0)})
  end

  routes do
    signal_source "/examples/basic/directive_agent"

    route "basic.directive.set_count", as: :set_count do
      action %{count: count, batch: batch},
        schema:
          Jido.Joi.object(%{
            count: Jido.Joi.integer(),
            batch: Jido.Joi.enum([:valid, :invalid, :dispatch_failure])
          }),
        context: context do
        second =
          case batch do
            :valid -> %Record{label: "second"}
            :invalid -> %Record{label: ""}
            :dispatch_failure -> %Record{label: "second", fail?: true}
          end

        {:ok, %{context.agent_state | count: count}, [%Record{label: "first"}, second, %Record{label: "third"}]}
      end
    end
  end
end

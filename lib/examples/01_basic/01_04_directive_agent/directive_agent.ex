defmodule Jido.Examples.DirectiveAgent do
  @moduledoc """
  An Agent that emits a batch of three recording Directives.

  The Effects Plugin records dispatch order and committed snapshots in a real
  supervised runtime. Invalid and failing batches test the commit boundary.
  """

  alias Jido.Examples.DirectiveAgent.{Effects, Record}

  defmodule Change do
    use Jido.Action,
      name: "basic_sdk_directive_batch",
      schema:
        Zoi.object(%{
          count: Zoi.integer(),
          batch: Zoi.enum([:valid, :invalid, :dispatch_failure])
        })

    @impl true
    def run(input, %{agent_state: state}) do
      second =
        case input.batch do
          :valid -> %Record{label: "second"}
          :invalid -> %Record{label: ""}
          :dispatch_failure -> %Record{label: "second", fail?: true}
        end

      {:ok, %{state | count: input.count},
       [%Record{label: "first"}, second, %Record{label: "third"}]}
    end
  end

  use Jido.Agent, name: "basic_sdk_directives"

  agent do
    schema Zoi.object(%{count: Zoi.integer() |> Zoi.default(0)})
    plugin Effects
  end

  routes do
    signal_source "/examples/basic/directive_agent"

    route "basic.effects.change", Change do
      define :set_count, args: [:count, :batch]
    end
  end
end

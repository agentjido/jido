defmodule Jido.Examples.ControlledTurnAgent do
  @moduledoc """
  An Agent with observable, controlled Action execution.

  Caller context carries an observer PID. Input selects an execution barrier. Release a
  blocked Action with `{:sdk_release, label}` sent to its reported worker PID.
  These messages control local observations and timing. Domain commands use
  Signals. Observer PIDs do not enter committed state or Directives.
  """

  alias Jido.Examples.DirectiveAgent.{Effects, Record}

  defmodule Change do
    use Jido.Action,
      name: "basic_sdk_controlled_turn",
      schema:
        Zoi.object(%{
          amount: Zoi.integer(),
          label: Zoi.string(),
          blocked?: Zoi.boolean() |> Zoi.default(false)
        })

    @impl true
    def run(input, %{agent_state: state, observer: observer} = context) do
      # These messages are test observation and a timing barrier. Domain
      # commands still use Signals; Jido.Exec and the Server remain real.
      send(observer, {:sdk_started, input.label, self(), state, Map.get(context, :request)})

      if input.blocked? do
        receive do
          {:sdk_release, label} when label == input.label -> :ok
        end
      end

      {:ok, %{state | count: state.count + input.amount, history: state.history ++ [input.label]},
       [%Record{label: input.label}]}
    end
  end

  use Jido.Agent, name: "basic_sdk_controlled_turn"

  agent do
    schema Zoi.object(%{
             count: Zoi.integer() |> Zoi.default(0),
             history: Zoi.list(Zoi.string()) |> Zoi.default([])
           })

    plugin Effects
  end

  routes do
    signal_source "/examples/basic/controlled_turn_agent"

    route "basic.controlled.change", Change do
      define :increment, args: [:amount, :label]
    end
  end
end

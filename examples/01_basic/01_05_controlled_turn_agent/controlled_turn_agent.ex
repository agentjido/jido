defmodule Jido.Examples.ControlledTurnAgent do
  @moduledoc """
  An Agent with observable, controlled Action execution.

  Caller context carries an observer PID and selects an execution barrier. Release
  a blocked Action with `{:sdk_release, label}` sent to its reported worker PID.
  These messages control local observations and timing. Domain commands use
  Signals. Observer PIDs do not enter Signals, committed state, or Directives.
  """

  use Jido.Agent, name: "basic_sdk_controlled_turn"

  agent do
    schema Zoi.object(%{
             count: Zoi.integer() |> Zoi.default(0),
             history: Zoi.list(Zoi.string()) |> Zoi.default([])
           })
  end

  routes do
    signal_source "/examples/basic/controlled_turn_agent"

    route "basic.controlled_turn.increment" do
      action %{amount: amount, label: label},
        name: "basic_sdk_controlled_turn",
        schema: Zoi.object(%{amount: Zoi.integer(), label: Zoi.string()}),
        context: context do
        state = context.agent_state

        # Observer messages and the barrier are transient execution controls.
        send(context.observer, {:sdk_started, label, self(), state, Map.get(context, :request)})

        if Map.get(context, :blocked?, false) do
          receive do
            {:sdk_release, ^label} -> :ok
          end
        end

        {:ok, %{state | count: state.count + amount, history: state.history ++ [label]}}
      end

      define :increment, args: [:amount, :label]
    end
  end
end

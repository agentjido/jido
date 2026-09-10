defmodule Jido.Examples.ProgressObservation do
  @moduledoc "Application progress and explicit waiting reasons through public Agent commands."
  use Jido.Agent, name: "research_progress_observation"

  agent do
    schema Zoi.object(%{
             waiting:
               Zoi.enum([:none, :approval, :child, :retry, :delivery]) |> Zoi.default(:none),
             status: Zoi.enum([:idle, :waiting, :completed, :cancelled]) |> Zoi.default(:idle),
             result: Zoi.string() |> Zoi.default("")
           })
  end

  routes do
    signal_source "/examples/research/progress_observation"

    route "examples.research.progress_observation.wait" do
      action %{reason: reason},
        schema: Zoi.object(%{reason: Zoi.enum([:approval, :child, :retry, :delivery])}),
        context: context do
        {:ok, %{context.agent_state | waiting: reason, status: :waiting}}
      end

      define :wait_for, args: [:reason]
    end

    route "examples.research.progress_observation.work" do
      action _input, schema: Zoi.object(%{}), context: context do
        table = Map.fetch!(context, :progress_table)
        for step <- 1..10, do: __MODULE__.Buffer.publish(table, %{step: step, total: 10})
        {:ok, %{context.agent_state | waiting: :none, status: :completed, result: "report"}}
      end

      define :work
    end

    route "examples.research.progress_observation.cancel" do
      action _input,
        schema: Zoi.object(%{}),
        context: context do
        {:ok, %{context.agent_state | waiting: :none, status: :cancelled}}
      end

      define :cancel_wait
    end
  end

  def view(server, table, cursor \\ 0) do
    %{
      committed: Jido.AgentServer.snapshot(server).agent.state,
      progress: __MODULE__.Buffer.read(table, cursor)
    }
  end
end

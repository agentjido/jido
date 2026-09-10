defmodule JidoTest.Examples.ProgressObservationWorker do
  @moduledoc false
  use Jido.Agent, name: "test_progress_observation_worker"

  agent do
    schema Zoi.object(%{
             waiting:
               Zoi.enum([:none, :approval, :child, :retry, :delivery]) |> Zoi.default(:none),
             status: Zoi.enum([:idle, :waiting, :completed, :cancelled]) |> Zoi.default(:idle),
             result: Zoi.string() |> Zoi.default("")
           })
  end

  routes do
    signal_source "/test/examples/progress_observation"

    route "test.examples.progress_observation.work" do
      action _input, schema: Zoi.object(%{}), context: context do
        for step <- 1..10 do
          Jido.Examples.ProgressObservation.Buffer.publish(context.progress_table, %{
            step: step,
            total: 10
          })
        end

        send(context.observer, {:working, self()})

        receive do
          :release ->
            {:ok, %{context.agent_state | status: :completed, result: "report"}}
        end
      end

      define :work
    end
  end
end

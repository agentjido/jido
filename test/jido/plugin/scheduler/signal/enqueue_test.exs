defmodule Jido.Plugin.Scheduler.Signal.EnqueueTest do
  use ExUnit.Case, async: true

  alias Jido.Plugin.Scheduler.Durable
  alias Jido.Plugin.Scheduler.Enqueue, as: EnqueueAction
  alias Jido.Plugin.Scheduler.Signal.Enqueue

  @data %{job_id: "job-1", generation: 1, scheduled_at: "2030-01-01T00:00:01Z"}

  test "the producer creates validated control Signals at both generation bounds" do
    for generation <- [0, 2_147_483_647] do
      data = %{@data | generation: generation}

      assert %Jido.Signal{
               type: "jido.scheduler.enqueue",
               source: "/jido/scheduler",
               data: ^data
             } = Durable.enqueue_signal("job-1", generation, ~U[2030-01-01 00:00:01Z])

      assert {:ok, ^data} = EnqueueAction.validate_params(data)
    end
  end

  test "the Signal constructor and receiving Action reject the same malformed input" do
    for data <- [
          Map.delete(@data, :generation),
          %{@data | generation: -1},
          %{@data | generation: 2_147_483_648},
          %{@data | generation: 1.0},
          %{@data | scheduled_at: "not-a-time"},
          %{@data | scheduled_at: "2030-01-01T01:00:01+01:00"}
        ] do
      assert {:error, _issues} = Enqueue.new(data)
      assert {:error, _error} = EnqueueAction.validate_params(data)
    end
  end
end

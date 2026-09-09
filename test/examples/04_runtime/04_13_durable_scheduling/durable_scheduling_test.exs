defmodule JidoTest.Examples.Runtime.DurableSchedulingTest do
  use JidoTest.AgentCase

  @moduletag group: :runtime

  alias Jido.AgentServer, as: Server
  alias Jido.Examples.PersistenceProbeStore
  alias Jido.Examples.ScheduledOccurrenceRecovery, as: Example

  setup do
    store = {PersistenceProbeStore, store: start_supervised!(PersistenceProbeStore)}
    {:ok, store: store}
  end

  test "an acknowledged occurrence stays complete after restore and scheduling continues", c do
    id = unique_id("example-durable-schedule")
    server = start_example(c, id, false)
    assert {:ok, _} = Example.arm_schedule(server, "job-1", "* * * * * *")

    [first | _] = await_ticks(server, 1)
    assert first.data == %{job_id: "job-1", generation: 1}
    assert first.occurrence.generation == 1
    assert Server.agent(server).state.scheduler.cron["job-1"].pending == nil

    ref = Process.monitor(server)
    Process.exit(server, :kill)
    assert_receive {:DOWN, ^ref, :process, ^server, :killed}, 1_000
    eventually(fn -> Jido.whereis_agent(c.jido, id) == nil end)

    restored = start_example(c, id, :required)

    assert Enum.any?(
             Server.agent(restored).state.ticks,
             &(&1.occurrence.id == first.occurrence.id)
           )

    ticks =
      eventually(
        fn ->
          ticks = Server.agent(restored).state.ticks
          if Enum.any?(ticks, &(&1.occurrence.id != first.occurrence.id)), do: ticks
        end,
        timeout: 4_000
      )

    assert Enum.count(ticks, &(&1.occurrence.id == first.occurrence.id)) == 1
    assert Enum.all?(ticks, &(&1.occurrence.generation == 1))
  end

  defp start_example(c, id, restore) do
    assert {:ok, server} =
             Jido.start_agent(c.jido, Example,
               id: id,
               persistence: c.store,
               restore: restore,
               restart: :temporary
             )

    server
  end

  defp await_ticks(server, count) do
    eventually(
      fn ->
        ticks = Server.agent(server).state.ticks
        if length(ticks) >= count, do: ticks
      end,
      timeout: 4_000
    )
  end
end

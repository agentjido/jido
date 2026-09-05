defmodule JidoTest.Plugin.DurableSchedulerTest do
  use ExUnit.Case, async: true
  @moduletag capability: "REC-03"

  alias Jido.Agent
  alias Jido.Examples.ScheduledOccurrenceRecovery, as: Example
  alias Jido.Plugin.Scheduler
  alias Jido.Plugin.Scheduler.Durable
  alias Jido.Signal

  @context %{jido: TestJido, partition: nil}
  @first ~U[2030-01-01 00:00:01Z]

  test "intent and completion use separate candidates and duplicate work is rejected" do
    {armed, _cron} = armed()
    assert {:ok, pending, [_queue]} = enqueue(armed, @first)
    assert armed.state.scheduler.cron["job-1"].pending == nil
    assert pending.state.ticks == []
    tick = pending.state.scheduler.cron["job-1"].pending
    assert {:ok, occurrence} = Scheduler.occurrence(tick)

    assert {:ok, completed, [%Scheduler.Acknowledge{occurrence_id: id}]} =
             Example.cmd(pending, tick)

    assert id == occurrence.id
    assert [%{occurrence: ^occurrence}] = completed.state.ticks
    assert completed.state.scheduler.cron["job-1"].pending == nil
    assert {:error, :stale_or_invalid_schedule_occurrence} = Example.cmd(completed, tick)
    assert {:ok, repeated, [_]} = enqueue(completed, @first)
    assert repeated == completed
  end

  test "the pending slot is bounded and newer busy slots are skipped" do
    {armed, _cron} = armed()
    assert {:ok, pending, [_]} = enqueue(armed, @first)
    tick = pending.state.scheduler.cron["job-1"].pending
    second = DateTime.add(@first, 1, :second)
    assert {:ok, busy, [_]} = enqueue(pending, second)
    assert busy.state.scheduler.cron["job-1"].pending == tick
    assert busy.state.scheduler.cron["job-1"].last_scheduled_at == DateTime.to_iso8601(second)
    assert {:ok, completed, [_]} = Example.cmd(busy, tick)
    assert {:ok, skipped, [_]} = enqueue(completed, second)
    assert skipped.state.scheduler.cron["job-1"].pending == nil
    assert {:ok, next, [_]} = enqueue(skipped, DateTime.add(second, 1, :second))

    assert {:ok, next_occurrence} =
             Scheduler.occurrence(next.state.scheduler.cron["job-1"].pending)

    assert next_occurrence.scheduled_at == "2030-01-01T00:00:03.000000Z"
  end

  test "replacing a generation retires both its pending tick and later enqueue requests" do
    {armed, _cron} = armed()
    assert {:ok, pending, [_]} = enqueue(armed, @first)
    tick = pending.state.scheduler.cron["job-1"].pending

    assert {:ok, replacement, [_]} =
             Example.cmd(pending, Example.arm_schedule_signal!("job-1", "* * * * * *"))

    assert replacement.state.generation == 2
    assert replacement.state.scheduler.cron["job-1"].pending == nil
    assert {:error, :stale_or_invalid_schedule_occurrence} = Example.cmd(replacement, tick)
    assert {:error, _} = enqueue(replacement, @first)
    assert {:ok, next, [_]} = enqueue(replacement, @first, 2)
    assert {:ok, old} = Scheduler.occurrence(tick)
    assert {:ok, new} = Scheduler.occurrence(next.state.scheduler.cron["job-1"].pending)
    refute old.id == new.id
  end

  test "cancellation and recreation reject the cancelled generation" do
    {armed, _cron} = armed()
    assert {:ok, pending, [_]} = enqueue(armed, @first)
    tick = pending.state.scheduler.cron["job-1"].pending
    assert {:ok, cancelled, [_]} = Example.cmd(pending, Example.cancel_schedule_signal!("job-1"))
    assert cancelled.state.scheduler.cron == %{}
    assert {:error, :stale_or_invalid_schedule_occurrence} = Example.cmd(cancelled, tick)
    assert {:error, _} = enqueue(cancelled, @first)

    assert {:ok, recreated, [_]} =
             Example.cmd(cancelled, Example.arm_schedule_signal!("job-1", "* * * * * *"))

    assert recreated.state.generation == 2
    assert {:error, _} = enqueue(recreated, @first)
    assert {:ok, _, [_]} = enqueue(recreated, @first, 2)
  end

  test "repeated definitions preserve progress and changed definitions need a new generation" do
    {armed, cron} = armed()
    assert {:ok, pending, [_]} = enqueue(armed, @first)
    state = pending.state.scheduler
    assert {:ok, ^state} = Scheduler.update_state(state, [cron], [])

    assert {:error, :schedule_generation_conflict} =
             Scheduler.update_state(state, [%{cron | cron: "*/2 * * * * *"}], [])

    assert {:error, :schedule_generation_conflict} =
             Scheduler.update_state(state, [%{cron | generation: 0}], [])
  end

  test "altered tick data, malformed pending state, and unknown acknowledgement are rejected" do
    {armed, _cron} = armed()
    assert {:ok, pending, [_]} = enqueue(armed, @first)
    tick = pending.state.scheduler.cron["job-1"].pending

    assert {:error, :stale_or_invalid_schedule_occurrence} =
             Example.cmd(pending, %{tick | data: %{job_id: "other"}})

    assert {:error, :unknown_schedule_occurrence} =
             Scheduler.update_state(
               pending.state.scheduler,
               [Scheduler.acknowledge("unknown")],
               []
             )

    {:ok, bad_tick} = Signal.put_context(tick, "jidoschedulegen", 2)
    invalid = put_in(pending.state, [:scheduler, :cron, "job-1", :pending], bad_tick)
    assert {:error, _} = Agent.transition(pending, invalid)
  end

  test "durable delivery requires an explicit generation" do
    signal = Signal.new!("test.tick", %{}, source: "/test")

    assert {:error, :durable_schedule_requires_generation} =
             Scheduler.validate_directive(
               Scheduler.cron("job-1", "* * * * *", signal, delivery: :durable),
               []
             )
  end

  defp armed do
    assert {:ok, armed, [cron]} =
             Example.cmd(
               Example.new!(id: "agent-1"),
               Example.arm_schedule_signal!("job-1", "* * * * * *")
             )

    {armed, cron}
  end

  defp enqueue(agent, time, generation \\ 1),
    do: Example.cmd(agent, Durable.enqueue_signal("job-1", generation, time), context: @context)
end

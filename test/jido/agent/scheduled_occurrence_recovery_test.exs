defmodule JidoTest.Agent.ScheduledOccurrenceRecoveryTest do
  use JidoTest.Case, async: false
  @moduletag capability: "REC-03"

  alias Jido.AgentServer, as: Server
  alias Jido.Examples.ScheduledOccurrenceRecovery, as: Example
  alias Jido.Plugin.Scheduler
  alias JidoTest.ScheduledOccurrenceFixtures.{Clock, DurableAgent}

  defmodule HeldFile do
    @moduledoc false
    @behaviour Jido.Persistence.Adapter
    @impl true
    defdelegate get(key, opts), to: Jido.Persistence.File
    @impl true
    defdelegate put(key, value, opts), to: Jido.Persistence.File
    @impl true
    defdelegate delete(key, opts), to: Jido.Persistence.File

    @impl true
    def compare_and_swap(key, expected, value, opts) do
      record = :erlang.binary_to_term(value, [:safe])

      hold? =
        record.checkpoint.state.ticks != [] and
          Elixir.Agent.get(Keyword.fetch!(opts, :barrier), & &1)

      stage = Keyword.get(opts, :stage, :before)
      if hold? and stage == :before, do: hold(record, opts, stage)
      result = Jido.Persistence.File.compare_and_swap(key, expected, value, opts)
      if hold? and stage == :after and result == :ok, do: hold(record, opts, stage)
      result
    end

    defp hold(record, opts, stage) do
      tick = List.last(record.checkpoint.state.ticks)
      send(Keyword.fetch!(opts, :observer), {:occurrence_write_held, self(), stage, tick})

      receive do
        :release -> :ok
      end
    end
  end

  defmodule FaultFile do
    @moduledoc false
    @behaviour Jido.Persistence.Adapter
    @impl true
    defdelegate get(key, opts), to: Jido.Persistence.File
    @impl true
    defdelegate put(key, value, opts), to: Jido.Persistence.File
    @impl true
    defdelegate delete(key, opts), to: Jido.Persistence.File

    @impl true
    def compare_and_swap(key, expected, value, opts) do
      state = :erlang.binary_to_term(value, [:safe]).checkpoint.state
      stage = Elixir.Agent.get(Keyword.fetch!(opts, :barrier), & &1)

      reject? =
        (stage == :result and state.ticks != []) or
          (stage == :intent and
             Enum.any?(state.scheduler.cron, fn {_job, spec} -> spec.pending != nil end))

      if reject? do
        send(Keyword.fetch!(opts, :observer), {:occurrence_write_rejected, stage})

        send(
          Keyword.fetch!(opts, :observer),
          {:occurrence_write_rejected_at, stage, System.monotonic_time(:millisecond)}
        )

        {:error, :test_storage_unavailable}
      else
        Jido.Persistence.File.compare_and_swap(key, expected, value, opts)
      end
    end
  end

  setup do
    start_supervised!({Clock, []})
    barrier = start_supervised!({Elixir.Agent, fn -> true end})
    path = Path.join(System.tmp_dir!(), unique_id("jido-occurrence-recovery"))
    on_exit(fn -> File.rm_rf!(path) end)
    persistence = {HeldFile, path: path, observer: self(), barrier: barrier}
    id = unique_id()
    {:ok, barrier: barrier, id: id, persistence: persistence}
  end

  test "an uncommitted occurrence is retried after Agent loss and clock advance", c do
    server = start_agent(c)
    assert {:ok, _} = Example.arm_schedule(server, "job-1", "* * * * * *")
    assert_receive {:occurrence_write_held, ^server, :before, lost}, 1_000
    assert lost.occurrence.scheduled_at == "2030-01-01T00:00:01.000000Z"

    saved = load_agent(c)
    assert saved.state.ticks == []
    assert saved.state.scheduler.cron["job-1"].generation == 1
    assert {:ok, occurrence} = Scheduler.occurrence(saved.state.scheduler.cron["job-1"].pending)
    assert occurrence.id == lost.occurrence.id

    kill(server)
    Elixir.Agent.update(c.barrier, fn _ -> false end)
    Clock.set(~U[2030-01-01 00:00:01.100000Z])
    restored = start_agent(c, restore: :required)
    ticks = await_occurrence(restored, lost.occurrence.id)
    assert Enum.count(ticks, &(&1.occurrence.id == lost.occurrence.id)) == 1
    refute Enum.find(ticks, &(&1.occurrence.id == lost.occurrence.id)).signal_id == lost.signal_id
  end

  test "completion survives Agent loss after its file write and does not repeat", c do
    {adapter, opts} = c.persistence
    c = %{c | persistence: {adapter, Keyword.put(opts, :stage, :after)}}
    server = start_agent(c)
    assert {:ok, _} = Example.arm_schedule(server, "job-1", "* * * * * *")
    assert_receive {:occurrence_write_held, ^server, :after, completed}, 1_000
    assert [^completed] = load_agent(c).state.ticks
    assert load_agent(c).state.scheduler.cron["job-1"].pending == nil
    kill(server)
    Elixir.Agent.update(c.barrier, fn _ -> false end)
    restored = start_agent(c, restore: :required)
    assert Server.agent(restored).state.ticks == [completed]
    Clock.set(~U[2030-01-01 00:00:01.100000Z])
    await_tick_count(restored, 2)
    assert [^completed, next] = Server.agent(restored).state.ticks
    assert next.occurrence.scheduled_at == "2030-01-01T00:00:02.000000Z"
  end

  test "Scheduler loss during delivery does not lose or repeat the business commit", c do
    server = start_agent(c)
    scheduler = Server.children(server)[{:plugin, Scheduler}].pid
    assert {:ok, _} = Example.arm_schedule(server, "job-1", "* * * * * *")
    assert_receive {:occurrence_write_held, ^server, :before, tick}, 1_000
    delivery = :sys.get_state(scheduler).delivery_task.pid
    monitor = Process.monitor(delivery)
    kill(scheduler)
    assert_receive {:DOWN, ^monitor, :process, ^delivery, _}, 1_000
    Elixir.Agent.update(c.barrier, fn _ -> false end)
    send(server, :release)
    await_occurrence(server, tick.occurrence.id)
    eventually(fn -> Server.children(server)[{:plugin, Scheduler}].pid != scheduler end)
    Clock.set(~U[2030-01-01 00:00:01.100000Z])
    await_tick_count(server, 2)
    assert [first, second] = Server.agent(server).state.ticks
    assert first.occurrence.id == tick.occurrence.id
    refute second.occurrence.id == first.occurrence.id
  end

  for stage <- [:intent, :result] do
    @stage stage
    test "a failed #{@stage} write preserves the last committed state and permits retry", c do
      {_adapter, opts} = c.persistence
      c = %{c | persistence: {FaultFile, opts}}
      Elixir.Agent.update(c.barrier, fn _ -> @stage end)
      server = start_agent(c)
      assert {:ok, _} = Example.arm_schedule(server, "job-1", "* * * * * *")
      assert_receive {:occurrence_write_rejected, @stage}, 1_000
      assert Server.agent(server).state.ticks == []
      assert load_agent(c).state.ticks == []
      pending = load_agent(c).state.scheduler.cron["job-1"].pending
      assert pending != nil == (@stage == :result)
      Elixir.Agent.update(c.barrier, fn _ -> false end)
      await_tick_count(server, 1)
      assert [_tick] = Server.agent(server).state.ticks
      assert Server.agent(server).state.scheduler.cron["job-1"].pending == nil
    end
  end

  test "configured delivery cadence retries the same saved work before acknowledgement", c do
    {_adapter, opts} = c.persistence
    c = %{c | persistence: {FaultFile, opts}}
    Elixir.Agent.update(c.barrier, fn _ -> :result end)
    server = start_agent(c)
    assert {:ok, _} = Example.arm_schedule(server, "job-1", "* * * * * *")

    assert_receive {:occurrence_write_rejected_at, :result, first}, 1_000
    pending = load_agent(c).state.scheduler.cron["job-1"].pending
    assert_receive {:occurrence_write_rejected_at, :result, second}, 1_000
    assert second - first >= 250
    assert load_agent(c).state.scheduler.cron["job-1"].pending == pending
    assert Server.agent(server).state.ticks == []

    Elixir.Agent.update(c.barrier, fn _ -> false end)
    {:ok, occurrence} = Scheduler.occurrence(pending)
    ticks = await_occurrence(server, occurrence.id)
    assert [%{occurrence: ^occurrence}] = ticks
    assert load_agent(c).state.scheduler.cron["job-1"].pending == nil
  end

  test "cancelling pending work survives restore and rejects the old delivery", c do
    {_adapter, opts} = c.persistence
    c = %{c | persistence: {FaultFile, opts}}
    Elixir.Agent.update(c.barrier, fn _ -> :result end)
    server = start_agent(c)
    assert {:ok, _} = Example.arm_schedule(server, "job-1", "* * * * * *")
    assert_receive {:occurrence_write_rejected, :result}, 1_000
    tick = Server.agent(server).state.scheduler.cron["job-1"].pending
    assert {:ok, cancelled} = Example.cancel_schedule(server, "job-1")
    assert cancelled.state.scheduler.cron == %{}
    assert {:error, _} = Server.call(server, tick)
    kill(server)
    Elixir.Agent.update(c.barrier, fn _ -> false end)
    restored = start_agent(c, restore: :required)
    assert Server.agent(restored) == cancelled
    assert {:error, _} = Server.call(restored, tick)
    assert {:ok, _} = Example.arm_schedule(restored, "job-1", "* * * * * *")
    await_tick_count(restored, 1)
    assert [%{occurrence: %{generation: 2}}] = Server.agent(restored).state.ticks
  end

  defp start_agent(c, opts \\ []) do
    opts = Keyword.merge([id: c.id, persistence: c.persistence, restart: :temporary], opts)
    assert {:ok, server} = Jido.start_agent(c.jido, DurableAgent, opts)
    server
  end

  defp load_agent(c) do
    assert {:ok, agent} =
             Jido.Persistence.load_agent(c.persistence, DurableAgent, c.id, instance: c.jido)

    agent
  end

  defp await_tick_count(server, count),
    do: eventually(fn -> length(Server.agent(server).state.ticks) >= count end, timeout: 2_000)

  defp await_occurrence(server, id) do
    eventually(
      fn ->
        ticks = Server.agent(server).state.ticks
        if Enum.any?(ticks, &(&1.occurrence.id == id)), do: ticks
      end,
      timeout: 2_000
    )
  end

  defp kill(pid) do
    ref = Process.monitor(pid)
    Process.exit(pid, :kill)
    assert_receive {:DOWN, ^ref, :process, ^pid, _}, 1_000
  end
end

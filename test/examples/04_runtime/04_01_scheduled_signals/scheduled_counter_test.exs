defmodule JidoTest.Examples.Runtime.ScheduledCounterTest do
  use JidoTest.AgentCase
  @moduletag :integration

  @moduletag group: :runtime
  @moduletag complexity: 2

  alias Jido.AgentServer, as: Server
  alias Jido.Examples.ScheduledCounter
  alias Jido.Plugin.Scheduler

  test "a scheduling Directive starts a later Signal and second Turn", %{jido: jido} do
    counter = start_agent!(jido, ScheduledCounter)

    assert {:ok, scheduled} = ScheduledCounter.schedule_once(counter, 10)
    assert scheduled.state.schedule_requests == 1
    assert scheduled.state.count == 0

    eventually(fn -> Server.agent(counter).state.count == 1 end)

    assert %{
             state: %{count: 1, schedule_requests: 1},
             state_version: 2
           } = agent_result(counter)
  end

  test "CRON Directives add and remove Scheduler runtime state", %{jido: jido} do
    counter = start_agent!(jido, ScheduledCounter)

    assert {:ok, enabled} = ScheduledCounter.enable_cron(counter, :heartbeat, "0 0 0 1 1 * 2099")
    assert enabled.state.cron_enabled

    assert {:ok, scheduler_state} = Server.plugin_state(counter, Scheduler)
    assert Map.has_key?(scheduler_state.cron, :heartbeat)

    assert {:ok, disabled} = ScheduledCounter.disable_cron(counter, :heartbeat)
    refute disabled.state.cron_enabled

    assert {:ok, scheduler_state} = Server.plugin_state(counter, Scheduler)
    refute Map.has_key?(scheduler_state.cron, :heartbeat)
  end

  test "invalid timer and CRON requests leave Agent and Plugin state unchanged", %{jido: jido} do
    counter = start_agent!(jido, ScheduledCounter, error_policy: :log_only)
    before = Server.snapshot(counter)
    assert {:error, _} = ScheduledCounter.schedule_once(counter, -1)
    assert {:error, _} = ScheduledCounter.enable_cron(counter, :invalid, "invalid cron")
    assert Server.snapshot(counter) == before
  end
end

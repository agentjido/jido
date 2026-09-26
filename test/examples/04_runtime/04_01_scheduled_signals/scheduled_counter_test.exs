defmodule JidoTest.Examples.Runtime.ScheduledCounterTest do
  use JidoTest.AgentCase

  @moduletag group: :runtime
  @moduletag complexity: 2

  alias Jido.AgentServer, as: Server
  alias Jido.Examples.ScheduledCounter
  alias Jido.Plugin.Scheduler

  test "a scheduling Directive starts a later Signal and second Turn", %{jido: jido} do
    counter = start_agent!(jido, ScheduledCounter)

    {:ok, route_signal_1} = ScheduledCounter.schedule_once_signal(%{delay_ms: 10})

    assert {:ok, scheduled} =
             Jido.AgentServer.call(counter, route_signal_1, [])

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

    {:ok, route_signal_2} =
      ScheduledCounter.enable_cron_signal(%{
        job_id: :heartbeat,
        expression: "0 0 0 1 1 * 2099"
      })

    assert {:ok, enabled} =
             Jido.AgentServer.call(counter, route_signal_2, [])

    assert enabled.state.cron_enabled

    assert {:ok, scheduler_state} = Server.plugin_state(counter, Scheduler)
    assert Map.has_key?(scheduler_state.cron, :heartbeat)

    {:ok, route_signal_3} = ScheduledCounter.disable_cron_signal(%{job_id: :heartbeat})

    assert {:ok, disabled} =
             Jido.AgentServer.call(counter, route_signal_3, [])

    refute disabled.state.cron_enabled

    assert {:ok, scheduler_state} = Server.plugin_state(counter, Scheduler)
    refute Map.has_key?(scheduler_state.cron, :heartbeat)
  end

  test "invalid timer and CRON requests leave Agent and Plugin state unchanged", %{jido: jido} do
    counter = start_agent!(jido, ScheduledCounter, error_policy: :log_only)
    before = Server.snapshot(counter)

    {:ok, route_signal_4} = ScheduledCounter.schedule_once_signal(%{delay_ms: -1})

    assert {:error, _} =
             Jido.AgentServer.call(counter, route_signal_4, [])

    {:ok, route_signal_5} =
      ScheduledCounter.enable_cron_signal(%{
        job_id: :invalid,
        expression: "invalid cron"
      })

    assert {:error, _} =
             Jido.AgentServer.call(counter, route_signal_5, [])

    assert Server.snapshot(counter) == before
  end
end

defmodule JidoTest.Agent.SchedulesIntegrationTest do
  use JidoTest.Case, async: false

  @moduletag :integration
  @moduletag capture_log: true

  defmodule TickAction do
    use Jido.Action, name: "tick", schema: []

    def run(_params, context) do
      count = Map.get(context.state, :tick_count, 0)
      {:ok, %{tick_count: count + 1}}
    end
  end

  defmodule ScheduledAgent do
    use Jido.Agent,
      name: "scheduled_agent",
      schema: [tick_count: [type: :integer, default: 0]],
      schedules: [
        {"* * * * * * *", "agent.tick", job_id: :tick}
      ]

    def signal_routes(_ctx) do
      [{"agent.tick", TickAction}]
    end
  end

  defmodule MultiScheduleAgent do
    use Jido.Agent,
      name: "multi_schedule_agent",
      schema: [tick_count: [type: :integer, default: 0]],
      schedules: [
        {"* * * * *", "heartbeat.tick", job_id: :heartbeat},
        {"@daily", "cleanup.run", job_id: :cleanup, timezone: "America/New_York"}
      ]

    def signal_routes(_ctx) do
      [{"heartbeat.tick", TickAction}, {"cleanup.run", TickAction}]
    end
  end

  defmodule NoScheduleAgent do
    use Jido.Agent,
      name: "no_schedule_agent",
      schema: [tick_count: [type: :integer, default: 0]]
  end

  describe "agent with schedules" do
    test "plugin_schedules/0 includes agent schedules" do
      schedules = ScheduledAgent.plugin_schedules()

      agent_schedules =
        Enum.filter(schedules, fn spec ->
          match?({:agent_schedule, _, _}, spec.job_id)
        end)

      assert length(agent_schedules) >= 1
    end

    test "agent schedules have correct job_id namespacing" do
      schedules = ScheduledAgent.plugin_schedules()

      agent_schedule =
        Enum.find(schedules, fn spec ->
          match?({:agent_schedule, _, _}, spec.job_id)
        end)

      assert agent_schedule.job_id == {:agent_schedule, "scheduled_agent", :tick}
    end

    test "agent schedules have correct signal_type" do
      schedules = ScheduledAgent.plugin_schedules()

      agent_schedule =
        Enum.find(schedules, fn spec ->
          match?({:agent_schedule, _, _}, spec.job_id)
        end)

      assert agent_schedule.signal_type == "agent.tick"
    end

    test "agent with no schedules has no agent schedules in plugin_schedules" do
      schedules = NoScheduleAgent.plugin_schedules()

      agent_schedules =
        Enum.filter(schedules, fn spec ->
          match?({:agent_schedule, _, _}, spec.job_id)
        end)

      assert agent_schedules == []
    end

    test "multiple schedules are all included" do
      schedules = MultiScheduleAgent.plugin_schedules()

      agent_schedules =
        Enum.filter(schedules, fn spec ->
          match?({:agent_schedule, _, _}, spec.job_id)
        end)

      assert length(agent_schedules) == 2

      signal_types = Enum.map(agent_schedules, & &1.signal_type) |> Enum.sort()
      assert signal_types == ["cleanup.run", "heartbeat.tick"]
    end
  end

  describe "agent schedule tick delivery" do
    test "schedule tick delivers signal and updates state", %{jido: jido} do
      pid = start_server(%{jido: jido}, ScheduledAgent)

      eventually_state(pid, fn state -> state.agent.state.tick_count > 0 end, timeout: 5_000)
    end
  end
end

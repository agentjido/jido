defmodule JidoTest.Agent.SchedulesTest do
  use ExUnit.Case, async: true

  alias Jido.Agent.Schedules

  describe "expand_schedules/2" do
    test "expands simple 2-tuple {cron, signal_type}" do
      result = Schedules.expand_schedules([{"* * * * *", "heartbeat.tick"}], "my_agent")

      assert [spec] = result
      assert spec.cron_expression == "* * * * *"
      assert spec.signal_type == "heartbeat.tick"
    end

    test "expands 3-tuple with job_id option" do
      result =
        Schedules.expand_schedules(
          [{"* * * * *", "heartbeat.tick", job_id: :heartbeat}],
          "my_agent"
        )

      assert [spec] = result
      assert spec.job_id == {:agent_schedule, "my_agent", :heartbeat}
    end

    test "expands 3-tuple with timezone option" do
      result =
        Schedules.expand_schedules(
          [{"* * * * *", "heartbeat.tick", timezone: "America/New_York"}],
          "my_agent"
        )

      assert [spec] = result
      assert spec.timezone == "America/New_York"
    end

    test "expands 3-tuple with both job_id and timezone" do
      result =
        Schedules.expand_schedules(
          [{"@daily", "cleanup.run", job_id: :cleanup, timezone: "America/New_York"}],
          "my_agent"
        )

      assert [spec] = result
      assert spec.job_id == {:agent_schedule, "my_agent", :cleanup}
      assert spec.timezone == "America/New_York"
    end

    test "defaults timezone to Etc/UTC" do
      [spec] = Schedules.expand_schedules([{"* * * * *", "tick"}], "agent")

      assert spec.timezone == "Etc/UTC"
    end

    test "defaults job_id to signal_type when not provided" do
      [spec] = Schedules.expand_schedules([{"* * * * *", "heartbeat.tick"}], "my_agent")

      assert spec.job_id == {:agent_schedule, "my_agent", "heartbeat.tick"}
    end

    test "namespaces job_id as {:agent_schedule, agent_name, value}" do
      [spec] =
        Schedules.expand_schedules(
          [{"* * * * *", "tick", job_id: :my_job}],
          "test_agent"
        )

      assert spec.job_id == {:agent_schedule, "test_agent", :my_job}
    end

    test "sets action to nil" do
      [spec] = Schedules.expand_schedules([{"* * * * *", "tick"}], "agent")

      assert spec.action == nil
    end

    test "expands multiple schedules" do
      schedules = [
        {"* * * * *", "heartbeat.tick", job_id: :heartbeat},
        {"@daily", "cleanup.run", job_id: :cleanup}
      ]

      result = Schedules.expand_schedules(schedules, "my_agent")

      assert length(result) == 2
      assert Enum.at(result, 0).signal_type == "heartbeat.tick"
      assert Enum.at(result, 1).signal_type == "cleanup.run"
    end

    test "returns empty list for empty input" do
      assert Schedules.expand_schedules([], "my_agent") == []
    end
  end

  describe "schedule_routes/1" do
    test "returns empty list" do
      schedules =
        Schedules.expand_schedules(
          [{"* * * * *", "heartbeat.tick", job_id: :heartbeat}],
          "my_agent"
        )

      assert Schedules.schedule_routes(schedules) == []
    end
  end
end

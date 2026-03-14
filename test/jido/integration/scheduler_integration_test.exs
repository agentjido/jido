defmodule JidoTest.Integration.SchedulerIntegrationTest do
  @moduledoc """
  Opt-in scheduler integration tests for invasive runtime failure scenarios.

  Run with:

      mix test --include scheduler_integration test/jido/integration/scheduler_integration_test.exs
  """

  use JidoTest.Case, async: false

  import ExUnit.CaptureLog
  import JidoTest.Support.SchedulerIntegrationHarness

  alias Jido.AgentServer
  alias Jido.Signal

  @moduletag :integration
  @moduletag :scheduler_integration
  @moduletag capture_log: true
  @moduletag timeout: 20_000

  defmodule PluginTickAction do
    @moduledoc false
    use Jido.Action, name: "plugin_tick", schema: []

    def run(_params, context) do
      count = Map.get(context.state, :tick_count, 0)
      ticks = Map.get(context.state, :ticks, [])
      {:ok, %{tick_count: count + 1, ticks: ticks ++ [%{source: :plugin_schedule}]}}
    end
  end

  defmodule ScheduledPlugin do
    @moduledoc false
    use Jido.Plugin,
      name: "scheduler_integration_plugin",
      state_key: :scheduler_integration_plugin,
      actions: [PluginTickAction],
      schedules: [
        {"* * * * * * *", PluginTickAction}
      ]
  end

  defmodule PluginScheduledAgent do
    @moduledoc false
    use Jido.Agent,
      name: "scheduler_integration_plugin_agent",
      schema: [
        tick_count: [type: :integer, default: 0],
        ticks: [type: {:list, :any}, default: []]
      ],
      plugins: [ScheduledPlugin]
  end

  defp plugin_job_id do
    {:plugin_schedule, :scheduler_integration_plugin, PluginTickAction}
  end

  describe "runtime scheduler failures" do
    test "cron job enters retry mode during tzdata outage and resumes after recovery", context do
      on_exit(fn ->
        {:ok, _} = Application.ensure_all_started(:tzdata)
      end)

      pid = start_cron_agent(context, id: unique_id("scheduler-retry"))

      assert :ok =
               register_cron(pid, "* * * * * * *",
                 job_id: :heartbeat,
                 timezone: "America/New_York"
               )

      job_pid = wait_for_job(pid, :heartbeat, timeout: 5_000)
      wait_for_tick_count(pid, 1, timeout: 5_000)

      server_ref = Process.monitor(pid)

      :ok = Application.stop(:tzdata)

      eventually(fn -> Process.alive?(pid) end, timeout: 2_000)

      eventually(fn -> Process.alive?(job_pid) and :sys.get_state(job_pid).retrying? end,
        timeout: 5_000
      )

      {:ok, state_during_outage} = AgentServer.state(pid)
      assert state_during_outage.cron_jobs[:heartbeat] == job_pid
      assert Process.alive?(job_pid)

      baseline = state_during_outage.agent.state.tick_count

      {:ok, _} = Application.ensure_all_started(:tzdata)

      eventually(fn -> Process.alive?(job_pid) and not :sys.get_state(job_pid).retrying? end,
        timeout: 5_000
      )

      wait_for_tick_count(pid, baseline + 1, timeout: 8_000)

      refute_received {:DOWN, ^server_ref, :process, ^pid, _reason}
    end

    test "non-durable cron payload is isolated and later cron registrations still work",
         context do
      pid = start_cron_agent(context, id: unique_id("scheduler-bad-message"))
      server_ref = Process.monitor(pid)

      bad_message =
        Signal.new!("cron.tick", %{reply_to: self(), kind: :bad_message}, source: "/test")

      good_message =
        Signal.new!("cron.tick", %{kind: :good_message}, source: "/test")

      log =
        capture_log(fn ->
          assert :ok =
                   register_cron(pid, "* * * * * * *",
                     job_id: :bad_message,
                     message: bad_message
                   )

          assert :ok =
                   register_cron(pid, "* * * * * * *",
                     job_id: :good_message,
                     message: good_message
                   )

          good_job_pid = wait_for_job(pid, :good_message, timeout: 5_000)
          assert Process.alive?(good_job_pid)

          eventually(
            fn ->
              Enum.count(ticks(pid), &(&1[:kind] == :good_message)) >= 1
            end,
            timeout: 5_000
          )
        end)

      state = state(pid)
      refute Map.has_key?(state.cron_jobs, :bad_message)
      refute Map.has_key?(state.cron_specs, :bad_message)
      assert is_pid(state.cron_jobs[:good_message])
      assert Process.alive?(state.cron_jobs[:good_message])
      refute_received {:DOWN, ^server_ref, :process, ^pid, _reason}
      assert log =~ "failed to register cron job :bad_message"
    end

    test "restarting one dynamic cron job does not disrupt sibling jobs", context do
      pid = start_cron_agent(context, id: unique_id("scheduler-siblings"))
      server_ref = Process.monitor(pid)

      alpha_message = Signal.new!("cron.tick", %{job: :alpha}, source: "/test")
      beta_message = Signal.new!("cron.tick", %{job: :beta}, source: "/test")

      assert :ok =
               register_cron(pid, "* * * * * * *",
                 job_id: :alpha,
                 message: alpha_message
               )

      assert :ok =
               register_cron(pid, "* * * * * * *",
                 job_id: :beta,
                 message: beta_message
               )

      alpha_job_pid = wait_for_job(pid, :alpha, timeout: 5_000)
      beta_job_pid = wait_for_job(pid, :beta, timeout: 5_000)

      eventually(
        fn ->
          ticks = ticks(pid)
          Enum.any?(ticks, &(&1[:job] == :alpha)) and Enum.any?(ticks, &(&1[:job] == :beta))
        end,
        timeout: 5_000
      )

      beta_baseline =
        ticks(pid)
        |> Enum.count(&(&1[:job] == :beta))

      Process.exit(alpha_job_pid, :kill)

      restarted_alpha_pid =
        eventually(
          fn ->
            state = state(pid)
            new_alpha_pid = state.cron_jobs[:alpha]

            if is_pid(new_alpha_pid) and new_alpha_pid != alpha_job_pid and
                 Process.alive?(new_alpha_pid) do
              new_alpha_pid
            else
              false
            end
          end,
          timeout: 6_000
        )

      assert Process.alive?(beta_job_pid)
      assert state(pid).cron_jobs[:beta] == beta_job_pid
      assert Process.alive?(restarted_alpha_pid)

      eventually(
        fn ->
          Enum.count(ticks(pid), &(&1[:job] == :beta)) >= beta_baseline + 1
        end,
        timeout: 5_000
      )

      refute_received {:DOWN, ^server_ref, :process, ^pid, _reason}
    end
  end

  describe "declarative schedule behavior" do
    test "agent schedules are runtime-only and do not populate durable cron_specs", context do
      pid = start_scheduled_agent(context, id: unique_id("scheduler-declarative"))

      job_id = scheduled_job_id()
      job_pid = wait_for_job(pid, job_id, timeout: 5_000)

      assert Process.alive?(job_pid)
      eventually(fn -> tick_count(pid) >= 1 end, timeout: 5_000)

      state = state(pid)
      assert state.cron_jobs[job_id] == job_pid
      assert state.cron_specs == %{}
    end

    test "agent schedules restart after abnormal scheduler death", context do
      pid = start_scheduled_agent(context, id: unique_id("scheduler-declarative-restart"))

      job_id = scheduled_job_id()
      original_job_pid = wait_for_job(pid, job_id, timeout: 5_000)
      assert Process.alive?(original_job_pid)

      Process.exit(original_job_pid, :kill)

      restarted_job_pid =
        eventually(
          fn ->
            state = state(pid)
            new_job_pid = state.cron_jobs[job_id]

            if is_pid(new_job_pid) and new_job_pid != original_job_pid and
                 Process.alive?(new_job_pid) do
              new_job_pid
            else
              false
            end
          end,
          timeout: 6_000
        )

      assert is_pid(restarted_job_pid)
      assert Process.alive?(restarted_job_pid)
    end
  end

  describe "plugin schedule behavior" do
    test "plugin schedules are runtime-only and deliver ticks", context do
      pid = start_server(context, PluginScheduledAgent, id: unique_id("scheduler-plugin-runtime"))

      job_id = plugin_job_id()
      job_pid = wait_for_job(pid, job_id, timeout: 5_000)

      assert Process.alive?(job_pid)

      eventually(
        fn ->
          tick_count(pid) >= 1 and Enum.any?(ticks(pid), &(&1[:source] == :plugin_schedule))
        end,
        timeout: 5_000
      )

      state = state(pid)
      assert state.cron_jobs[job_id] == job_pid
      assert state.cron_specs == %{}
    end

    test "plugin schedules restart after abnormal scheduler death", context do
      pid = start_server(context, PluginScheduledAgent, id: unique_id("scheduler-plugin-restart"))

      job_id = plugin_job_id()
      original_job_pid = wait_for_job(pid, job_id, timeout: 5_000)
      assert Process.alive?(original_job_pid)

      Process.exit(original_job_pid, :kill)

      restarted_job_pid =
        eventually(
          fn ->
            current_state = state(pid)
            new_job_pid = current_state.cron_jobs[job_id]

            if is_pid(new_job_pid) and new_job_pid != original_job_pid and
                 Process.alive?(new_job_pid) do
              new_job_pid
            else
              false
            end
          end,
          timeout: 6_000
        )

      assert is_pid(restarted_job_pid)
      assert Process.alive?(restarted_job_pid)
    end
  end
end

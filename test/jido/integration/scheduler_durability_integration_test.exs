defmodule JidoTest.Integration.SchedulerDurabilityIntegrationTest do
  @moduledoc """
  Opt-in scheduler durability tests that exercise storage-backed hibernate/thaw
  and corrupted replay paths.

  Run with:

      mix test --include scheduler_integration test/jido/integration/scheduler_durability_integration_test.exs
  """

  use JidoTest.Case, async: false

  import ExUnit.CaptureLog
  import JidoTest.Support.SchedulerIntegrationHarness

  alias Jido.Agent.InstanceManager
  alias Jido.AgentServer
  alias Jido.Persist
  alias Jido.Signal
  alias Jido.Storage.ETS

  alias JidoTest.Support.SchedulerIntegrationHarness.{
    CronAgent,
    ScheduledCronAgent
  }

  @moduletag :integration
  @moduletag :scheduler_integration
  @moduletag capture_log: true
  @moduletag timeout: 25_000

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

  defmodule RestoreCountingAgent do
    @moduledoc false
    use Jido.Agent,
      name: "scheduler_restore_counting_agent",
      schema: [
        counter: [type: :integer, default: 0]
      ]

    @impl true
    def signal_routes(_ctx), do: []

    @impl true
    def restore(data, _ctx) do
      case :persistent_term.get({__MODULE__, :notify_pid}, nil) do
        pid when is_pid(pid) -> send(pid, {:restore_called, data.id})
        _ -> :ok
      end

      agent = new(id: data.id)
      restored_state = Map.merge(agent.state, Map.get(data, :state, %{}))
      {:ok, %{agent | state: restored_state}}
    end
  end

  defp start_manager(context, agent_module, opts \\ []) do
    manager_name =
      Keyword.get(
        opts,
        :name,
        :"scheduler_integration_manager_#{System.unique_integer([:positive])}"
      )

    table = Keyword.get(opts, :table, unique_table("scheduler_integration_storage"))
    idle_timeout = Keyword.get(opts, :idle_timeout, 200)

    {:ok, _} =
      start_supervised(
        InstanceManager.child_spec(
          name: manager_name,
          agent: agent_module,
          idle_timeout: idle_timeout,
          storage: {ETS, table: table},
          agent_opts: [jido: context.jido]
        )
      )

    on_exit(fn ->
      :persistent_term.erase({InstanceManager, manager_name})
      cleanup_storage_tables(table)
      {:ok, _} = Application.ensure_all_started(:tzdata)
    end)

    %{manager: manager_name, table: table}
  end

  defp get_attached(manager, key, opts \\ []) do
    eventually(
      fn ->
        case InstanceManager.get(manager, key, opts) do
          {:ok, pid} ->
            case AgentServer.attach(pid) do
              :ok -> {:ok, pid}
              _ -> false
            end

          _ ->
            false
        end
      end,
      timeout: 3_000
    )
  end

  defp wait_for_idle_shutdown(pid) do
    ref = Process.monitor(pid)
    assert_receive {:DOWN, ^ref, :process, ^pid, {:shutdown, :idle_timeout}}, 2_000
  end

  describe "storage-backed declarative schedules" do
    test "declarative schedules re-register after idle hibernate and remain runtime-only",
         context do
      %{manager: manager} = start_manager(context, ScheduledCronAgent)
      instance_key = "declarative-scheduler-1"

      {:ok, pid1} = get_attached(manager, instance_key)
      job_id = scheduled_job_id()
      job_pid1 = wait_for_job(pid1, job_id, timeout: 5_000)

      assert Process.alive?(job_pid1)
      eventually(fn -> tick_count(pid1) >= 1 end, timeout: 5_000)

      state1 = state(pid1)
      assert state1.cron_specs == %{}

      :ok = AgentServer.detach(pid1)
      wait_for_idle_shutdown(pid1)

      {:ok, pid2} = get_attached(manager, instance_key)
      job_pid2 = wait_for_job(pid2, job_id, timeout: 5_000)

      assert Process.alive?(job_pid2)
      refute job_pid1 == job_pid2

      state2 = state(pid2)
      assert state2.cron_specs == %{}

      :ok = AgentServer.detach(pid2)
    end
  end

  describe "corrupted replay cleanup" do
    test "mixed durable replay restores valid spec and drops malformed sibling", context do
      %{manager: manager, table: table} = start_manager(context, CronAgent)
      instance_key = "mixed-replay-1"
      scheduler_key = Jido.Scheduler.cron_specs_state_key()
      checkpoint_key = checkpoint_key(CronAgent, manager, instance_key)

      good_signal = Signal.new!("cron.tick", %{kind: :good_replay}, source: "/test")

      checkpoint = %{
        version: 1,
        agent_module: CronAgent,
        id: instance_key,
        state:
          %{tick_count: 0, ticks: []}
          |> Map.put(scheduler_key, %{
            good: Jido.Scheduler.build_cron_spec("* * * * * * *", good_signal, "Etc/UTC"),
            broken: %{cron_expression: 123, message: :tick, timezone: "Etc/UTC"}
          }),
        thread: nil
      }

      assert :ok = ETS.put_checkpoint(checkpoint_key, checkpoint, table: table)

      log =
        capture_log(fn ->
          {:ok, pid} = get_attached(manager, instance_key)

          good_job_pid = wait_for_job(pid, :good, timeout: 5_000)
          assert Process.alive?(good_job_pid)

          eventually(
            fn ->
              Enum.any?(ticks(pid), &(&1[:kind] == :good_replay))
            end,
            timeout: 5_000
          )

          current_state = state(pid)
          assert Map.has_key?(current_state.cron_jobs, :good)
          assert Map.has_key?(current_state.cron_specs, :good)
          refute Map.has_key?(current_state.cron_jobs, :broken)
          refute Map.has_key?(current_state.cron_specs, :broken)

          :ok = AgentServer.detach(pid)
          wait_for_idle_shutdown(pid)
        end)

      assert log =~ "dropped malformed persisted cron spec"

      eventually(
        fn ->
          case ETS.get_checkpoint(checkpoint_key, table: table) do
            {:ok, updated_checkpoint} ->
              persisted_specs = Map.get(updated_checkpoint.state || %{}, scheduler_key, %{})
              Map.has_key?(persisted_specs, :good) and not Map.has_key?(persisted_specs, :broken)

            _ ->
              false
          end
        end,
        timeout: 3_000
      )
    end

    test "malformed persisted cron specs are logged, dropped on thaw, and cleaned on next hibernate",
         context do
      %{manager: manager, table: table} = start_manager(context, CronAgent)
      instance_key = "corrupt-cron-spec-1"
      scheduler_key = Jido.Scheduler.cron_specs_state_key()
      checkpoint_key = checkpoint_key(CronAgent, manager, instance_key)

      checkpoint = %{
        version: 1,
        agent_module: CronAgent,
        id: instance_key,
        state:
          %{tick_count: 0, ticks: []}
          |> Map.put(scheduler_key, %{
            broken: %{cron_expression: 123, message: :tick, timezone: "Etc/UTC"}
          }),
        thread: nil
      }

      assert :ok = ETS.put_checkpoint(checkpoint_key, checkpoint, table: table)

      log =
        capture_log(fn ->
          {:ok, pid} = get_attached(manager, instance_key)

          assert state(pid).cron_specs == %{}
          assert state(pid).cron_jobs == %{}

          :ok = AgentServer.detach(pid)
          wait_for_idle_shutdown(pid)
        end)

      assert log =~ "dropped malformed persisted cron spec"

      eventually(
        fn ->
          case ETS.get_checkpoint(checkpoint_key, table: table) do
            {:ok, updated_checkpoint} ->
              scheduler_state = Map.get(updated_checkpoint.state || %{}, scheduler_key, %{})
              scheduler_state == %{}

            _ ->
              false
          end
        end,
        timeout: 3_000
      )
    end

    test "replay failure during thaw is scrubbed from persisted state after re-hibernate",
         context do
      %{manager: manager, table: table} = start_manager(context, CronAgent)
      instance_key = "transient-replay-failure-1"
      scheduler_key = Jido.Scheduler.cron_specs_state_key()
      checkpoint_key = checkpoint_key(CronAgent, manager, instance_key)

      cron_specs = %{
        skipped:
          Jido.Scheduler.build_cron_spec(
            "* * * * * * *",
            Signal.new!("cron.tick", %{kind: :replayed}, source: "/test"),
            "America/New_York"
          )
      }

      checkpoint = %{
        version: 1,
        agent_module: CronAgent,
        id: instance_key,
        state:
          %{tick_count: 0, ticks: []}
          |> Map.put(scheduler_key, cron_specs),
        thread: nil
      }

      assert :ok = ETS.put_checkpoint(checkpoint_key, checkpoint, table: table)

      log =
        capture_log(fn ->
          :ok = Application.stop(:tzdata)

          {:ok, pid} = get_attached(manager, instance_key)

          eventually(
            fn ->
              current_state = state(pid)
              current_state.cron_specs == %{} and current_state.cron_jobs == %{}
            end,
            timeout: 5_000
          )

          :ok = AgentServer.detach(pid)
          {:ok, _} = Application.ensure_all_started(:tzdata)
          wait_for_idle_shutdown(pid)
        end)

      assert log =~ "failed to register cron job :skipped"

      eventually(
        fn ->
          case ETS.get_checkpoint(checkpoint_key, table: table) do
            {:ok, updated_checkpoint} ->
              persisted_specs = Map.get(updated_checkpoint.state || %{}, scheduler_key, %{})
              persisted_specs == %{}

            _ ->
              false
          end
        end,
        timeout: 3_000
      )
    end

    test "bad durable replay does not block plugin schedules on thaw", context do
      %{manager: manager, table: table} = start_manager(context, PluginScheduledAgent)
      instance_key = "plugin-thaw-with-bad-durable-1"
      scheduler_key = Jido.Scheduler.cron_specs_state_key()
      checkpoint_key = checkpoint_key(PluginScheduledAgent, manager, instance_key)

      checkpoint = %{
        version: 1,
        agent_module: PluginScheduledAgent,
        id: instance_key,
        state:
          %{tick_count: 0, ticks: []}
          |> Map.put(scheduler_key, %{
            bad_dynamic: %{cron_expression: 123, message: :tick, timezone: "Etc/UTC"}
          }),
        thread: nil
      }

      assert :ok = ETS.put_checkpoint(checkpoint_key, checkpoint, table: table)

      log =
        capture_log(fn ->
          {:ok, pid} = get_attached(manager, instance_key)

          plugin_pid = wait_for_job(pid, plugin_job_id(), timeout: 5_000)
          assert Process.alive?(plugin_pid)

          eventually(
            fn ->
              tick_count(pid) >= 1 and
                Enum.any?(ticks(pid), &(&1[:source] == :plugin_schedule))
            end,
            timeout: 5_000
          )

          current_state = state(pid)
          assert Map.has_key?(current_state.cron_jobs, plugin_job_id())
          refute Map.has_key?(current_state.cron_specs, :bad_dynamic)

          :ok = AgentServer.detach(pid)
          wait_for_idle_shutdown(pid)
        end)

      assert log =~ "dropped malformed persisted cron spec"
    end

    test "custom restore callback runs exactly once through InstanceManager.get/2", context do
      %{manager: manager, table: table} = start_manager(context, RestoreCountingAgent)
      instance_key = "restore-once-1"

      :persistent_term.put({RestoreCountingAgent, :notify_pid}, self())

      on_exit(fn ->
        :persistent_term.erase({RestoreCountingAgent, :notify_pid})
      end)

      agent = RestoreCountingAgent.new(id: "restore-once-agent")
      agent = %{agent | state: %{agent.state | counter: 41}}

      assert :ok =
               Persist.hibernate(
                 {ETS, table: table},
                 RestoreCountingAgent,
                 {manager, instance_key},
                 agent
               )

      {:ok, pid} = get_attached(manager, instance_key)
      assert_receive {:restore_called, "restore-once-agent"}, 2_000
      refute_receive {:restore_called, "restore-once-agent"}, 500

      assert state(pid).agent.state.counter == 41

      :ok = AgentServer.detach(pid)
    end

    test "write-through cron register and cancel do not rewrite corrupt checkpoint state",
         context do
      %{manager: manager, table: table} = start_manager(context, CronAgent)
      register_key = "corrupt-write-through-register"
      register_checkpoint_key = checkpoint_key(CronAgent, manager, register_key)

      register_checkpoint = %{
        version: 1,
        agent_module: CronAgent,
        id: register_key,
        marker: :register_marker,
        state: [],
        thread: nil
      }

      assert :ok = ETS.put_checkpoint(register_checkpoint_key, register_checkpoint, table: table)

      {:ok, register_pid} = get_attached(manager, register_key)

      assert :ok =
               register_cron(register_pid, "* * * * * * *", job_id: :write_through_register)

      wait_for_job(register_pid, :write_through_register, timeout: 5_000)

      eventually(
        fn ->
          case ETS.get_checkpoint(register_checkpoint_key, table: table) do
            {:ok, checkpoint} ->
              checkpoint.state == [] and checkpoint.marker == :register_marker

            _ ->
              false
          end
        end,
        timeout: 3_000
      )

      cancel_key = "corrupt-write-through-cancel"
      cancel_checkpoint_key = checkpoint_key(CronAgent, manager, cancel_key)

      {:ok, cancel_pid} = get_attached(manager, cancel_key)

      assert :ok =
               register_cron(cancel_pid, "* * * * * * *", job_id: :write_through_cancel)

      wait_for_job(cancel_pid, :write_through_cancel, timeout: 5_000)

      corrupt_cancel_checkpoint = %{
        version: 1,
        agent_module: CronAgent,
        id: cancel_key,
        marker: :cancel_marker,
        state: [],
        thread: nil
      }

      assert :ok =
               ETS.put_checkpoint(cancel_checkpoint_key, corrupt_cancel_checkpoint, table: table)

      assert :ok = cancel_cron(cancel_pid, :write_through_cancel)

      eventually(
        fn ->
          case ETS.get_checkpoint(cancel_checkpoint_key, table: table) do
            {:ok, checkpoint} ->
              checkpoint.state == [] and checkpoint.marker == :cancel_marker

            _ ->
              false
          end
        end,
        timeout: 3_000
      )
    end
  end
end

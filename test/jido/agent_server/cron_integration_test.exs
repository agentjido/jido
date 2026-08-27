defmodule JidoTest.AgentServer.CronIntegrationTest do
  use JidoTest.Case, async: false

  import ExUnit.CaptureLog

  @moduletag :integration
  @moduletag capture_log: true

  alias Jido.Agent.Directive
  alias Jido.AgentServer
  alias Jido.Persist
  alias Jido.Signal
  alias Jido.Storage.ETS

  defmodule CronCountAction do
    @moduledoc false
    use Jido.Action, name: "cron_count", schema: []

    def run(params, context) do
      count = Map.get(context.state, :tick_count, 0)
      ticks = Map.get(context.state, :ticks, [])
      {:ok, %{tick_count: count + 1, ticks: ticks ++ [params]}}
    end
  end

  defmodule RegisterCronAction do
    @moduledoc false
    use Jido.Action, name: "register_cron", schema: []

    def run(params, _context) do
      cron_expr = Map.get(params, :cron)
      job_id = Map.get(params, :job_id)
      message = Map.get(params, :message, Signal.new!(%{type: "cron.tick", source: "/test"}))
      timezone = Map.get(params, :timezone)

      directive = Directive.cron(cron_expr, message, job_id: job_id, timezone: timezone)
      {:ok, %{}, [directive]}
    end
  end

  defmodule CancelCronAction do
    @moduledoc false
    use Jido.Action, name: "cancel_cron", schema: []

    def run(%{job_id: job_id}, _context) do
      {:ok, %{}, [Directive.cron_cancel(job_id)]}
    end
  end

  defmodule CronTestAgent do
    @moduledoc false
    use Jido.Agent,
      name: "cron_test_agent",
      schema:
        Zoi.object(%{
          tick_count: Zoi.integer() |> Zoi.default(0),
          ticks: Zoi.list(Zoi.any()) |> Zoi.default([])
        })

    def signal_routes(_ctx) do
      [
        {"register_cron", RegisterCronAction},
        {"cancel_cron", CancelCronAction},
        {"cron.tick", CronCountAction}
      ]
    end
  end

  defp job_pid(job), do: GenServer.whereis(job)
  defp job_alive?(job), do: is_pid(job_pid(job))

  describe "cron job registration" do
    test "agent can register a cron job", %{jido: jido} do
      {:ok, pid} = AgentServer.start_link(agent: CronTestAgent, id: "cron-test-1", jido: jido)

      register_signal =
        Signal.new!(%{
          type: "register_cron",
          source: "/test",
          data: %{
            job_id: :heartbeat,
            cron: "* * * * *"
          }
        })

      :ok = AgentServer.cast(pid, register_signal)

      state = eventually_state(pid, fn state -> Map.has_key?(state.cron_jobs, :heartbeat) end)

      job = state.cron_jobs[:heartbeat]
      assert job_alive?(job)

      GenServer.stop(pid)
    end

    test "agent can register multiple cron jobs", %{jido: jido} do
      {:ok, pid} = AgentServer.start_link(agent: CronTestAgent, id: "cron-test-2", jido: jido)

      for {job_id, cron_expr} <- [heartbeat: "* * * * *", daily: "@daily", hourly: "@hourly"] do
        register_signal =
          Signal.new!(%{
            type: "register_cron",
            source: "/test",
            data: %{job_id: job_id, cron: cron_expr}
          })

        :ok = AgentServer.cast(pid, register_signal)
      end

      state = eventually_state(pid, fn state -> map_size(state.cron_jobs) == 3 end)

      assert Map.has_key?(state.cron_jobs, :heartbeat)
      assert Map.has_key?(state.cron_jobs, :daily)
      assert Map.has_key?(state.cron_jobs, :hourly)

      for {_id, job} <- state.cron_jobs do
        assert job_alive?(job)
      end

      GenServer.stop(pid)
    end

    test "registering same job_id updates existing job (upsert)", %{jido: jido} do
      {:ok, pid} = AgentServer.start_link(agent: CronTestAgent, id: "cron-test-3", jido: jido)

      register_signal1 =
        Signal.new!(%{
          type: "register_cron",
          source: "/test",
          data: %{job_id: :updatable, cron: "* * * * *"}
        })

      :ok = AgentServer.cast(pid, register_signal1)

      state1 = eventually_state(pid, fn state -> Map.has_key?(state.cron_jobs, :updatable) end)
      first_job_pid = state1.cron_jobs[:updatable]
      assert job_alive?(first_job_pid)

      register_signal2 =
        Signal.new!(%{
          type: "register_cron",
          source: "/test",
          data: %{job_id: :updatable, cron: "@hourly"}
        })

      :ok = AgentServer.cast(pid, register_signal2)

      state2 =
        eventually_state(pid, fn state ->
          state.cron_jobs[:updatable] != first_job_pid
        end)

      assert map_size(state2.cron_jobs) == 1
      second_job_pid = state2.cron_jobs[:updatable]
      assert job_alive?(second_job_pid)

      refute first_job_pid == second_job_pid

      GenServer.stop(pid)
    end

    test "failed upsert preserves the existing runtime job and durable spec", %{jido: jido} do
      {:ok, pid} =
        AgentServer.start_link(agent: CronTestAgent, id: "cron-test-upsert-invalid", jido: jido)

      register_signal =
        Signal.new!(%{
          type: "register_cron",
          source: "/test",
          data: %{job_id: :stable, cron: "* * * * *"}
        })

      :ok = AgentServer.cast(pid, register_signal)

      state1 =
        eventually_state(pid, fn state ->
          Map.has_key?(state.cron_jobs, :stable) and Map.has_key?(state.cron_specs, :stable)
        end)

      job_pid = state1.cron_jobs[:stable]
      cron_spec = state1.cron_specs[:stable]

      invalid_update_signal =
        Signal.new!(%{
          type: "register_cron",
          source: "/test",
          data: %{job_id: :stable, cron: "not-a-cron"}
        })

      :ok = AgentServer.cast(pid, invalid_update_signal)

      state2 =
        eventually_state(pid, fn state ->
          state.cron_jobs[:stable] == job_pid and state.cron_specs[:stable] == cron_spec
        end)

      assert job_alive?(job_pid)
      assert state2.cron_specs[:stable].cron_expression == "* * * * *"

      GenServer.stop(pid)
    end

    test "invalid dynamic cron input logs and preserves the agent", %{jido: jido} do
      {:ok, pid} =
        AgentServer.start_link(agent: CronTestAgent, id: "cron-test-invalid-type", jido: jido)

      register_signal =
        Signal.new!(%{
          type: "register_cron",
          source: "/test",
          data: %{job_id: :invalid_type, cron: 123}
        })

      log =
        capture_log(fn ->
          assert {:ok, _agent} = AgentServer.call(pid, register_signal)

          state =
            eventually(fn ->
              case AgentServer.state(pid) do
                {:ok, state} -> state
                _ -> nil
              end
            end)

          refute Map.has_key?(state.cron_jobs, :invalid_type)
          refute Map.has_key?(state.cron_specs, :invalid_type)
        end)

      assert Process.alive?(pid)
      assert log =~ "failed to register cron job :invalid_type"

      GenServer.stop(pid)
    end

    test "rejects non-durable cron messages during registration", %{jido: jido} do
      {:ok, pid} =
        AgentServer.start_link(agent: CronTestAgent, id: "cron-test-invalid-message", jido: jido)

      register_signal =
        Signal.new!(%{
          type: "register_cron",
          source: "/test",
          data: %{job_id: :invalid_message, cron: "* * * * *", message: {:notify, self()}}
        })

      log =
        capture_log(fn ->
          assert {:ok, _agent} = AgentServer.call(pid, register_signal)

          state =
            eventually(fn ->
              case AgentServer.state(pid) do
                {:ok, state} -> state
                _ -> nil
              end
            end)

          refute Map.has_key?(state.cron_jobs, :invalid_message)
          refute Map.has_key?(state.cron_specs, :invalid_message)
        end)

      assert log =~ "invalid_message"

      GenServer.stop(pid)
    end

    test "malformed restored cron spec is logged and dropped", %{jido: jido} do
      scheduler_key = Jido.Scheduler.cron_specs_state_key()

      agent =
        CronTestAgent.new(id: "cron-test-restored-invalid")
        |> then(fn agent ->
          cron_specs = %{skipped: %{cron_expression: 123, message: :tick, timezone: "Etc/UTC"}}

          %{agent | state: Map.put(agent.state, scheduler_key, cron_specs)}
        end)

      log =
        capture_log(fn ->
          {:ok, pid} =
            AgentServer.start_link(
              agent: agent,
              agent_module: CronTestAgent,
              id: "cron-test-restored-invalid",
              jido: jido
            )

          assert Process.alive?(pid)

          state = eventually_state(pid, fn state -> map_size(state.cron_jobs) == 0 end)

          assert map_size(state.cron_jobs) == 0
          refute Map.has_key?(state.cron_specs, :skipped)

          GenServer.stop(pid)
        end)

      assert log =~ "dropped malformed persisted cron spec :skipped"
    end

    test "replay failure drops the durable spec and does not re-persist it", %{jido: jido} do
      scheduler_key = Jido.Scheduler.cron_specs_state_key()
      table = :"cron_replay_drop_#{System.unique_integer([:positive])}"

      restored_signal =
        Signal.new!(%{
          type: "cron.tick",
          source: "/test"
        })

      agent =
        CronTestAgent.new(id: "cron-test-restored-transient")
        |> then(fn agent ->
          cron_specs = %{
            skipped:
              Jido.Scheduler.build_cron_spec("* * * * *", restored_signal, "Invalid/Nowhere")
          }

          %{agent | state: Map.put(agent.state, scheduler_key, cron_specs)}
        end)

      log =
        capture_log(fn ->
          {:ok, pid} =
            AgentServer.start_link(
              agent: agent,
              agent_module: CronTestAgent,
              id: "cron-test-restored-transient",
              jido: jido
            )

          {:ok, state} = AgentServer.state(pid)
          refute Map.has_key?(state.cron_jobs, :skipped)
          refute Map.has_key?(state.cron_specs, :skipped)

          persisted_agent = Jido.Scheduler.attach_staged_cron_specs(state.agent, state.cron_specs)
          assert :ok = Persist.hibernate({ETS, table: table}, persisted_agent)

          {:ok, checkpoint} =
            ETS.get_checkpoint({CronTestAgent, "cron-test-restored-transient"}, table: table)

          refute Map.has_key?(checkpoint.state || %{}, scheduler_key)

          GenServer.stop(pid)
        end)

      assert log =~ "failed to register cron job :skipped"
    end

    test "cron job with timezone", %{jido: jido} do
      {:ok, pid} = AgentServer.start_link(agent: CronTestAgent, id: "cron-test-4", jido: jido)

      register_signal =
        Signal.new!(%{
          type: "register_cron",
          source: "/test",
          data: %{
            job_id: :timezone_test,
            cron: "0 9 * * *",
            timezone: "Etc/UTC"
          }
        })

      :ok = AgentServer.cast(pid, register_signal)

      state = eventually_state(pid, fn state -> Map.has_key?(state.cron_jobs, :timezone_test) end)
      assert job_alive?(state.cron_jobs[:timezone_test])

      GenServer.stop(pid)
    end

    test "invalid cron directive is isolated and agent survives", %{jido: jido} do
      {:ok, pid} = AgentServer.start_link(agent: CronTestAgent, id: "cron-test-4b", jido: jido)
      ref = Process.monitor(pid)

      register_signal =
        Signal.new!(%{
          type: "register_cron",
          source: "/test",
          data: %{
            job_id: :invalid_cron,
            cron: "definitely-not-a-cron"
          }
        })

      :ok = AgentServer.cast(pid, register_signal)

      eventually(fn -> Process.alive?(pid) end)
      {:ok, state} = AgentServer.state(pid)
      refute Map.has_key?(state.cron_jobs, :invalid_cron)
      refute Map.has_key?(state.cron_specs, :invalid_cron)
      refute_received {:DOWN, ^ref, :process, ^pid, _}

      GenServer.stop(pid)
    end

    test "invalid timezone directive is isolated and agent survives", %{jido: jido} do
      {:ok, pid} = AgentServer.start_link(agent: CronTestAgent, id: "cron-test-4c", jido: jido)
      ref = Process.monitor(pid)

      register_signal =
        Signal.new!(%{
          type: "register_cron",
          source: "/test",
          data: %{
            job_id: :invalid_tz,
            cron: "0 9 * * *",
            timezone: "Invalid/Nowhere"
          }
        })

      :ok = AgentServer.cast(pid, register_signal)

      eventually(fn -> Process.alive?(pid) end)
      {:ok, state} = AgentServer.state(pid)
      refute Map.has_key?(state.cron_jobs, :invalid_tz)
      refute Map.has_key?(state.cron_specs, :invalid_tz)
      refute_received {:DOWN, ^ref, :process, ^pid, _}

      GenServer.stop(pid)
    end

    test "auto-generates job_id if not provided", %{jido: jido} do
      {:ok, pid} = AgentServer.start_link(agent: CronTestAgent, id: "cron-test-5", jido: jido)

      register_signal =
        Signal.new!(%{
          type: "register_cron",
          source: "/test",
          data: %{cron: "* * * * *"}
        })

      :ok = AgentServer.cast(pid, register_signal)

      state = eventually_state(pid, fn state -> map_size(state.cron_jobs) == 1 end)

      [job_id] = Map.keys(state.cron_jobs)
      assert is_reference(job_id)

      GenServer.stop(pid)
    end
  end

  describe "runtime failure isolation and recovery" do
    test "abnormal cron job death does not kill agent and job restarts", %{jido: jido} do
      {:ok, pid} = AgentServer.start_link(agent: CronTestAgent, id: "cron-test-9a", jido: jido)
      server_ref = Process.monitor(pid)

      register_signal =
        Signal.new!(%{
          type: "register_cron",
          source: "/test",
          data: %{job_id: :restartable, cron: "* * * * *"}
        })

      :ok = AgentServer.cast(pid, register_signal)

      state1 = eventually_state(pid, fn state -> Map.has_key?(state.cron_jobs, :restartable) end)
      job = state1.cron_jobs[:restartable]
      original_job_pid = job_pid(job)
      assert is_pid(original_job_pid)

      Process.exit(original_job_pid, :kill)

      restarted_job_pid =
        eventually(
          fn ->
            new_pid = job_pid(job)
            if is_pid(new_pid) and new_pid != original_job_pid, do: new_pid, else: false
          end,
          timeout: 6_000
        )

      assert is_pid(restarted_job_pid)
      assert Process.alive?(pid)
      refute_received {:DOWN, ^server_ref, :process, ^pid, _}

      GenServer.stop(pid)
    end

    test "cancel removes durable spec after a supervised restart", %{jido: jido} do
      {:ok, pid} = AgentServer.start_link(agent: CronTestAgent, id: "cron-test-9b", jido: jido)

      register_signal =
        Signal.new!(%{
          type: "register_cron",
          source: "/test",
          data: %{job_id: :gone_runtime, cron: "* * * * *"}
        })

      :ok = AgentServer.cast(pid, register_signal)

      state1 = eventually_state(pid, fn state -> Map.has_key?(state.cron_jobs, :gone_runtime) end)
      job = state1.cron_jobs[:gone_runtime]
      original_job_pid = job_pid(job)
      assert is_pid(original_job_pid)

      Process.exit(original_job_pid, :kill)

      eventually_state(
        pid,
        fn state ->
          restarted_pid = job_pid(job)

          is_pid(restarted_pid) and restarted_pid != original_job_pid and
            Map.has_key?(state.cron_specs, :gone_runtime)
        end,
        timeout: 6_000
      )

      cancel_signal =
        Signal.new!(%{
          type: "cancel_cron",
          source: "/test",
          data: %{job_id: :gone_runtime}
        })

      :ok = AgentServer.cast(pid, cancel_signal)

      eventually_state(
        pid,
        fn state ->
          not Map.has_key?(state.cron_jobs, :gone_runtime) and
            not Map.has_key?(state.cron_specs, :gone_runtime)
        end,
        timeout: 2_000
      )

      GenServer.stop(pid)
    end
  end

  describe "cron job cancellation" do
    test "agent can cancel a cron job", %{jido: jido} do
      {:ok, pid} = AgentServer.start_link(agent: CronTestAgent, id: "cron-test-6", jido: jido)

      register_signal =
        Signal.new!(%{
          type: "register_cron",
          source: "/test",
          data: %{job_id: :cancellable, cron: "* * * * *"}
        })

      :ok = AgentServer.cast(pid, register_signal)

      state1 = eventually_state(pid, fn state -> Map.has_key?(state.cron_jobs, :cancellable) end)
      job = state1.cron_jobs[:cancellable]
      assert job_alive?(job)

      cancel_signal =
        Signal.new!(%{
          type: "cancel_cron",
          source: "/test",
          data: %{job_id: :cancellable}
        })

      :ok = AgentServer.cast(pid, cancel_signal)

      eventually_state(pid, fn state -> not Map.has_key?(state.cron_jobs, :cancellable) end)

      eventually(fn -> not job_alive?(job) end)

      GenServer.stop(pid)
    end

    test "cancelling non-existent job is safe", %{jido: jido} do
      {:ok, pid} = AgentServer.start_link(agent: CronTestAgent, id: "cron-test-7", jido: jido)

      cancel_signal =
        Signal.new!(%{
          type: "cancel_cron",
          source: "/test",
          data: %{job_id: :nonexistent}
        })

      :ok = AgentServer.cast(pid, cancel_signal)

      eventually_state(pid, fn state -> map_size(state.cron_jobs) == 0 end)

      GenServer.stop(pid)
    end

    test "can cancel and re-register same job_id", %{jido: jido} do
      {:ok, pid} = AgentServer.start_link(agent: CronTestAgent, id: "cron-test-8", jido: jido)

      register_signal =
        Signal.new!(%{
          type: "register_cron",
          source: "/test",
          data: %{job_id: :toggle, cron: "* * * * *"}
        })

      :ok = AgentServer.cast(pid, register_signal)

      eventually_state(pid, fn state -> Map.has_key?(state.cron_jobs, :toggle) end)

      cancel_signal =
        Signal.new!(%{
          type: "cancel_cron",
          source: "/test",
          data: %{job_id: :toggle}
        })

      :ok = AgentServer.cast(pid, cancel_signal)

      eventually_state(pid, fn state -> not Map.has_key?(state.cron_jobs, :toggle) end)

      register_signal2 =
        Signal.new!(%{
          type: "register_cron",
          source: "/test",
          data: %{job_id: :toggle, cron: "@hourly"}
        })

      :ok = AgentServer.cast(pid, register_signal2)

      state2 = eventually_state(pid, fn state -> Map.has_key?(state.cron_jobs, :toggle) end)
      assert job_alive?(state2.cron_jobs[:toggle])

      GenServer.stop(pid)
    end
  end

  describe "cleanup on agent termination" do
    test "cron jobs are cleaned up when agent stops normally", %{jido: jido} do
      {:ok, pid} = AgentServer.start_link(agent: CronTestAgent, id: "cron-test-10", jido: jido)

      register_signal =
        Signal.new!(%{
          type: "register_cron",
          source: "/test",
          data: %{job_id: :cleanup_test, cron: "* * * * *"}
        })

      :ok = AgentServer.cast(pid, register_signal)

      state = eventually_state(pid, fn state -> Map.has_key?(state.cron_jobs, :cleanup_test) end)
      job = state.cron_jobs[:cleanup_test]
      assert job_alive?(job)

      GenServer.stop(pid)

      eventually(fn -> not job_alive?(job) end)
    end

    test "multiple cron jobs are all cleaned up on termination", %{jido: jido} do
      {:ok, pid} = AgentServer.start_link(agent: CronTestAgent, id: "cron-test-11", jido: jido)

      job_ids = [:job1, :job2, :job3]

      for job_id <- job_ids do
        register_signal =
          Signal.new!(%{
            type: "register_cron",
            source: "/test",
            data: %{job_id: job_id, cron: "* * * * *"}
          })

        :ok = AgentServer.cast(pid, register_signal)
      end

      state = eventually_state(pid, fn state -> map_size(state.cron_jobs) == 3 end)
      jobs = Enum.map(job_ids, fn id -> state.cron_jobs[id] end)

      for job <- jobs do
        assert job_alive?(job)
      end

      GenServer.stop(pid)

      for job <- jobs do
        eventually(fn -> not job_alive?(job) end)
      end
    end
  end

  describe "job scoping" do
    test "different agents can use same job_id without collision", %{jido: jido} do
      {:ok, pid1} = AgentServer.start_link(agent: CronTestAgent, id: "cron-test-12a", jido: jido)
      {:ok, pid2} = AgentServer.start_link(agent: CronTestAgent, id: "cron-test-12b", jido: jido)

      for pid <- [pid1, pid2] do
        register_signal =
          Signal.new!(%{
            type: "register_cron",
            source: "/test",
            data: %{job_id: :shared_name, cron: "* * * * *"}
          })

        :ok = AgentServer.cast(pid, register_signal)
      end

      state1 = eventually_state(pid1, fn state -> Map.has_key?(state.cron_jobs, :shared_name) end)
      state2 = eventually_state(pid2, fn state -> Map.has_key?(state.cron_jobs, :shared_name) end)

      job_pid1 = state1.cron_jobs[:shared_name]
      job_pid2 = state2.cron_jobs[:shared_name]

      refute job_pid1 == job_pid2
      assert job_alive?(job_pid1)
      assert job_alive?(job_pid2)

      GenServer.stop(pid1)
      GenServer.stop(pid2)
    end
  end
end

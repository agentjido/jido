defmodule JidoTest.AgentServer.CronIntegrationTest do
  use JidoTest.Case, async: false

  @moduletag :integration
  @moduletag capture_log: true

  alias Jido.AgentServer
  alias Jido.Agent.Directive
  alias Jido.Signal
  alias JidoTest.WaitHelpers

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
      schema: [
        tick_count: [type: :integer, default: 0],
        ticks: [type: {:list, :any}, default: []]
      ]

    def signal_routes do
      [
        {"register_cron", RegisterCronAction},
        {"cancel_cron", CancelCronAction},
        {"cron.tick", CronCountAction}
      ]
    end
  end

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
      await_cron_job(pid, :heartbeat)

      {:ok, state} = AgentServer.state(pid)
      assert Map.has_key?(state.cron_jobs, :heartbeat)

      job_pid = state.cron_jobs[:heartbeat]
      assert is_pid(job_pid)
      assert Process.alive?(job_pid)

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

      await_cron_jobs(pid, 3)

      {:ok, state} = AgentServer.state(pid)
      assert map_size(state.cron_jobs) == 3
      assert Map.has_key?(state.cron_jobs, :heartbeat)
      assert Map.has_key?(state.cron_jobs, :daily)
      assert Map.has_key?(state.cron_jobs, :hourly)

      # All should be pids
      for {_id, job_pid} <- state.cron_jobs do
        assert is_pid(job_pid)
        assert Process.alive?(job_pid)
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
      await_cron_job(pid, :updatable)

      {:ok, state1} = AgentServer.state(pid)
      first_job_pid = state1.cron_jobs[:updatable]
      assert is_pid(first_job_pid)

      register_signal2 =
        Signal.new!(%{
          type: "register_cron",
          source: "/test",
          data: %{job_id: :updatable, cron: "@hourly"}
        })

      :ok = AgentServer.cast(pid, register_signal2)

      WaitHelpers.wait_until(
        fn ->
          case AgentServer.state(pid) do
            {:ok, state} ->
              map_size(state.cron_jobs) == 1 and
                Map.get(state.cron_jobs, :updatable) != first_job_pid

            _ ->
              false
          end
        end,
        label: "cron job upsert to replace pid"
      )

      {:ok, state2} = AgentServer.state(pid)
      assert map_size(state2.cron_jobs) == 1
      second_job_pid = state2.cron_jobs[:updatable]
      assert is_pid(second_job_pid)

      # The old pid should have been cancelled (may or may not be alive depending on timing)
      # The new pid should be different
      refute first_job_pid == second_job_pid

      GenServer.stop(pid)
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
            timezone: "America/New_York"
          }
        })

      :ok = AgentServer.cast(pid, register_signal)
      await_cron_job(pid, :timezone_test)

      {:ok, state} = AgentServer.state(pid)
      assert Map.has_key?(state.cron_jobs, :timezone_test)
      assert is_pid(state.cron_jobs[:timezone_test])

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
      await_cron_jobs(pid, 1)

      {:ok, state} = AgentServer.state(pid)
      assert map_size(state.cron_jobs) == 1

      [job_id] = Map.keys(state.cron_jobs)
      assert is_reference(job_id)

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
      await_cron_job(pid, :cancellable)

      {:ok, state1} = AgentServer.state(pid)
      assert Map.has_key?(state1.cron_jobs, :cancellable)
      job_pid = state1.cron_jobs[:cancellable]
      assert is_pid(job_pid)
      assert Process.alive?(job_pid)
      ref = Process.monitor(job_pid)

      cancel_signal =
        Signal.new!(%{
          type: "cancel_cron",
          source: "/test",
          data: %{job_id: :cancellable}
        })

      :ok = AgentServer.cast(pid, cancel_signal)
      await_cron_job_removed(pid, :cancellable)

      {:ok, state2} = AgentServer.state(pid)
      refute Map.has_key?(state2.cron_jobs, :cancellable)

      # The job pid should no longer be alive
      assert_receive {:DOWN, ^ref, :process, ^job_pid, _reason}, 1000

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
      await_cron_jobs(pid, 0)

      {:ok, state} = AgentServer.state(pid)
      assert map_size(state.cron_jobs) == 0

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
      await_cron_job(pid, :toggle)

      cancel_signal =
        Signal.new!(%{
          type: "cancel_cron",
          source: "/test",
          data: %{job_id: :toggle}
        })

      :ok = AgentServer.cast(pid, cancel_signal)
      await_cron_job_removed(pid, :toggle)

      {:ok, state1} = AgentServer.state(pid)
      refute Map.has_key?(state1.cron_jobs, :toggle)

      register_signal2 =
        Signal.new!(%{
          type: "register_cron",
          source: "/test",
          data: %{job_id: :toggle, cron: "@hourly"}
        })

      :ok = AgentServer.cast(pid, register_signal2)
      await_cron_job(pid, :toggle)

      {:ok, state2} = AgentServer.state(pid)
      assert Map.has_key?(state2.cron_jobs, :toggle)
      assert is_pid(state2.cron_jobs[:toggle])

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
      await_cron_job(pid, :cleanup_test)

      {:ok, state} = AgentServer.state(pid)
      job_pid = state.cron_jobs[:cleanup_test]
      assert is_pid(job_pid)
      assert Process.alive?(job_pid)
      ref = Process.monitor(job_pid)

      GenServer.stop(pid)

      # The job pid should no longer be alive after agent terminates
      assert_receive {:DOWN, ^ref, :process, ^job_pid, _reason}, 1000
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

      await_cron_jobs(pid, 3)

      {:ok, state} = AgentServer.state(pid)
      job_pids = Enum.map(job_ids, fn id -> state.cron_jobs[id] end)
      refs = Enum.map(job_pids, &Process.monitor/1)

      # All pids should be alive before termination
      for job_pid <- job_pids do
        assert is_pid(job_pid)
        assert Process.alive?(job_pid)
      end

      GenServer.stop(pid)

      # All pids should be dead after termination
      Enum.zip(refs, job_pids)
      |> Enum.each(fn {ref, job_pid} ->
        assert_receive {:DOWN, ^ref, :process, ^job_pid, _reason}, 1000
      end)
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

      WaitHelpers.wait_until(
        fn ->
          case {AgentServer.state(pid1), AgentServer.state(pid2)} do
            {{:ok, state1}, {:ok, state2}} ->
              Map.has_key?(state1.cron_jobs, :shared_name) and
                Map.has_key?(state2.cron_jobs, :shared_name)

            _ ->
              false
          end
        end,
        label: "cron job to register on both agents"
      )

      {:ok, state1} = AgentServer.state(pid1)
      {:ok, state2} = AgentServer.state(pid2)

      assert Map.has_key?(state1.cron_jobs, :shared_name)
      assert Map.has_key?(state2.cron_jobs, :shared_name)

      job_pid1 = state1.cron_jobs[:shared_name]
      job_pid2 = state2.cron_jobs[:shared_name]

      # Each agent has its own SchedEx process
      refute job_pid1 == job_pid2
      assert Process.alive?(job_pid1)
      assert Process.alive?(job_pid2)

      GenServer.stop(pid1)
      GenServer.stop(pid2)
    end
  end

  defp await_cron_job(pid, job_id, opts \\ []) do
    WaitHelpers.wait_until(
      fn ->
        case AgentServer.state(pid) do
          {:ok, state} -> Map.has_key?(state.cron_jobs, job_id)
          _ -> false
        end
      end,
      Keyword.merge([label: "cron job #{inspect(job_id)} registration"], opts)
    )
  end

  defp await_cron_jobs(pid, count, opts \\ []) do
    WaitHelpers.wait_until(
      fn ->
        case AgentServer.state(pid) do
          {:ok, state} -> map_size(state.cron_jobs) == count
          _ -> false
        end
      end,
      Keyword.merge([label: "cron job count #{count}"], opts)
    )
  end

  defp await_cron_job_removed(pid, job_id, opts \\ []) do
    WaitHelpers.wait_until(
      fn ->
        case AgentServer.state(pid) do
          {:ok, state} -> not Map.has_key?(state.cron_jobs, job_id)
          _ -> false
        end
      end,
      Keyword.merge([label: "cron job #{inspect(job_id)} removal"], opts)
    )
  end
end

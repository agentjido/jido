defmodule JidoTest.Support.SchedulerIntegrationHarness do
  @moduledoc false

  import JidoTest.Eventually

  alias Jido.Agent.Directive
  alias Jido.AgentServer
  alias Jido.Signal
  alias Jido.Scheduler

  defmodule TickAction do
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
      timezone = Map.get(params, :timezone)
      message = Map.get(params, :message, Signal.new!(%{type: "cron.tick", source: "/test"}))

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

  defmodule CronAgent do
    @moduledoc false
    use Jido.Agent,
      name: "scheduler_integration_agent",
      schema: [
        tick_count: [type: :integer, default: 0],
        ticks: [type: {:list, :any}, default: []]
      ]

    def signal_routes(_ctx) do
      [
        {"register_cron", RegisterCronAction},
        {"cancel_cron", CancelCronAction},
        {"cron.tick", TickAction}
      ]
    end
  end

  defmodule ScheduledCronAgent do
    @moduledoc false
    use Jido.Agent,
      name: "scheduler_integration_scheduled_agent",
      schema: [
        tick_count: [type: :integer, default: 0],
        ticks: [type: {:list, :any}, default: []]
      ],
      schedules: [
        {"* * * * * * *", "cron.tick", job_id: :scheduled_heartbeat}
      ]

    def signal_routes(_ctx) do
      [
        {"cron.tick", TickAction}
      ]
    end
  end

  def start_cron_agent(context, opts \\ []) do
    JidoTest.Case.start_server(
      context,
      CronAgent,
      Keyword.put_new(opts, :id, JidoTest.Case.unique_id("scheduler-integration"))
    )
  end

  def start_scheduled_agent(context, opts \\ []) do
    JidoTest.Case.start_server(
      context,
      ScheduledCronAgent,
      Keyword.put_new(opts, :id, JidoTest.Case.unique_id("scheduler-scheduled"))
    )
  end

  def scheduled_job_id do
    {:agent_schedule, "scheduler_integration_scheduled_agent", :scheduled_heartbeat}
  end

  def unique_table(prefix \\ "scheduler_integration") do
    :"#{prefix}_#{System.unique_integer([:positive])}"
  end

  def cleanup_storage_tables(table) do
    Enum.each([:"#{table}_checkpoints", :"#{table}_threads", :"#{table}_thread_meta"], fn t ->
      try do
        :ets.delete(t)
      rescue
        _ -> :ok
      end
    end)
  end

  def checkpoint_key(agent_module, manager, key) do
    {agent_module, {manager, key}}
  end

  def stage_cron_specs(agent, cron_specs) when is_map(cron_specs) do
    Scheduler.attach_staged_cron_specs(agent, cron_specs)
  end

  def register_cron(pid, cron_expr, opts \\ []) do
    message = Keyword.get(opts, :message, Signal.new!(%{type: "cron.tick", source: "/test"}))

    signal =
      Signal.new!(%{
        type: "register_cron",
        source: "/test",
        data: %{
          cron: cron_expr,
          job_id: Keyword.get(opts, :job_id),
          timezone: Keyword.get(opts, :timezone),
          message: message
        }
      })

    AgentServer.cast(pid, signal)
  end

  def cancel_cron(pid, job_id) do
    signal =
      Signal.new!(%{
        type: "cancel_cron",
        source: "/test",
        data: %{job_id: job_id}
      })

    AgentServer.cast(pid, signal)
  end

  def wait_for_job(pid, job_id, opts \\ []) do
    eventually(
      fn ->
        case AgentServer.state(pid) do
          {:ok, state} ->
            case Map.get(state.cron_jobs, job_id) do
              job_pid when is_pid(job_pid) ->
                if Process.alive?(job_pid), do: job_pid, else: false

              _ ->
                false
            end

          _ ->
            false
        end
      end,
      opts
    )
  end

  def wait_for_tick_count(pid, count, opts \\ []) do
    eventually_state(
      pid,
      fn state ->
        tick_count = state.agent.state.tick_count
        if tick_count >= count, do: tick_count, else: false
      end,
      opts
    )
  end

  def tick_count(pid) do
    state = state(pid)
    state.agent.state.tick_count
  end

  def ticks(pid) do
    state = state(pid)
    state.agent.state.ticks
  end

  def state(pid) do
    {:ok, state} = AgentServer.state(pid)
    state
  end
end

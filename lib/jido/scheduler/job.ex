defmodule Jido.Scheduler.Job do
  @moduledoc false

  use GenServer

  @shutdown_timeout 500

  @type option ::
          {:cron_expr, String.t()}
          | {:fun, (-> term())}
          | {:name, GenServer.name()}
          | {:owner_pid, pid()}
          | {:timezone, String.t()}

  @doc false
  @spec child_spec([option()]) :: Supervisor.child_spec()
  def child_spec(opts) do
    %{
      id: Keyword.fetch!(opts, :name),
      start: {__MODULE__, :start_link, [opts]},
      restart: :transient,
      shutdown: @shutdown_timeout,
      type: :worker
    }
  end

  @doc false
  @spec start_link([option()]) :: GenServer.on_start()
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, Keyword.take(opts, [:name]))
  end

  @impl true
  def init(opts) do
    Process.flag(:trap_exit, true)

    owner_pid = Keyword.fetch!(opts, :owner_pid)

    if Process.alive?(owner_pid) do
      owner_ref = Process.monitor(owner_pid)
      fun = Keyword.fetch!(opts, :fun)
      cron_expr = Keyword.fetch!(opts, :cron_expr)
      timezone = Keyword.fetch!(opts, :timezone)

      case SchedEx.run_every(fun, cron_expr, timezone: timezone) do
        {:ok, runner_pid} ->
          {:ok,
           %{
             owner_ref: owner_ref,
             runner_pid: runner_pid
           }}

        {:error, reason} ->
          {:stop, {:invalid_cron, reason}}

        :ignore ->
          {:stop, {:invalid_schedule, cron_expr, timezone}}
      end
    else
      :ignore
    end
  end

  @impl true
  def handle_info(
        {:DOWN, owner_ref, :process, _owner_pid, _reason},
        %{owner_ref: owner_ref} = state
      ) do
    {:stop, :normal, state}
  end

  def handle_info({:EXIT, runner_pid, reason}, %{runner_pid: runner_pid} = state) do
    {:stop, {:sched_ex_runner_exit, reason}, state}
  end

  def handle_info(_message, state), do: {:noreply, state}

  @impl true
  def handle_cast(:stop, state), do: {:stop, :normal, state}

  @impl true
  def terminate(_reason, state) do
    if Process.alive?(state.runner_pid) do
      SchedEx.cancel(state.runner_pid)
    end

    :ok
  end
end

defmodule Jido.Scheduler.Job do
  @moduledoc false

  use GenServer

  require Logger

  alias Crontab.CronExpression.Parser
  alias Crontab.Scheduler, as: CronScheduler

  @tick :tick
  @retry_schedule :retry_schedule
  @retry_delay_ms 1_000
  @max_schedule_attempts 8
  @time_zone_database Tzdata.TimeZoneDatabase

  @type schedule :: %{
          required(:cron_expr) => String.t(),
          required(:cron) => Crontab.CronExpression.t(),
          required(:timezone) => String.t()
        }

  @type state :: %{
          fun: (-> term()),
          cron_expr: String.t(),
          cron: Crontab.CronExpression.t(),
          timezone: String.t(),
          timer_ref: reference() | nil,
          retrying?: boolean,
          callback_workers: %{reference() => pid()},
          owner_pid: pid() | nil,
          owner_ref: reference() | nil
        }

  @doc false
  @spec prepare_schedule(String.t(), String.t()) :: {:ok, schedule()} | {:error, term()}
  def prepare_schedule(cron_expr, timezone)
      when is_binary(cron_expr) and is_binary(timezone) do
    with {:ok, cron} <- parse_cron(cron_expr),
         {:ok, now} <- now_in_timezone(timezone),
         {:ok, _next_at} <- next_scheduled_at(cron, timezone, now) do
      {:ok, %{cron_expr: cron_expr, cron: cron, timezone: timezone}}
    end
  end

  @doc false
  @spec next_scheduled_at(Crontab.CronExpression.t(), String.t(), DateTime.t()) ::
          {:ok, DateTime.t()} | {:error, term()}
  def next_scheduled_at(cron, timezone, from)
      when is_struct(cron, Crontab.CronExpression) and is_binary(timezone) and
             is_struct(from, DateTime) do
    do_next_scheduled_at(cron, timezone, from, @max_schedule_attempts)
  end

  @spec start((-> term()), schedule(), pid() | nil) :: GenServer.on_start()
  def start(
        fun,
        %{cron_expr: cron_expr, cron: cron, timezone: timezone} = schedule,
        owner_pid \\ nil
      )
      when is_function(fun, 0) and is_binary(cron_expr) and
             is_struct(cron, Crontab.CronExpression) and
             is_binary(timezone) and (is_nil(owner_pid) or is_pid(owner_pid)) do
    GenServer.start(__MODULE__, Map.merge(schedule, %{fun: fun, owner_pid: owner_pid}))
  end

  @spec start_link((-> term()), schedule()) :: GenServer.on_start()
  def start_link(fun, %{cron_expr: cron_expr, cron: cron, timezone: timezone} = schedule)
      when is_function(fun, 0) and is_binary(cron_expr) and
             is_struct(cron, Crontab.CronExpression) and
             is_binary(timezone) do
    GenServer.start_link(__MODULE__, Map.put(schedule, :fun, fun))
  end

  @impl true
  def init(%{fun: fun, cron_expr: cron_expr, cron: cron, timezone: timezone} = init_state) do
    owner_pid = Map.get(init_state, :owner_pid)
    owner_ref = if is_pid(owner_pid), do: Process.monitor(owner_pid), else: nil

    with {:ok, timer_ref} <- schedule_next_tick(cron, timezone) do
      {:ok,
       %{
         fun: fun,
         cron_expr: cron_expr,
         cron: cron,
         timezone: timezone,
         timer_ref: timer_ref,
         retrying?: false,
         callback_workers: %{},
         owner_pid: owner_pid,
         owner_ref: owner_ref
       }}
    else
      {:error, reason} ->
        {:stop, reason}
    end
  end

  @impl true
  def handle_info(@tick, state) do
    state =
      state
      |> schedule_after_tick()
      |> spawn_callback_worker()

    {:noreply, state}
  end

  def handle_info(@retry_schedule, state), do: {:noreply, retry_schedule(state)}

  def handle_info({:DOWN, ref, :process, pid, reason}, %{owner_ref: ref, owner_pid: pid} = state) do
    {:stop, {:owner_down, reason}, state}
  end

  def handle_info({:DOWN, ref, :process, _pid, _reason}, state) do
    {:noreply, %{state | callback_workers: Map.delete(state.callback_workers, ref)}}
  end

  def handle_info(_other, state), do: {:noreply, state}

  @impl true
  def terminate(_reason, %{
        timer_ref: timer_ref,
        callback_workers: callback_workers,
        owner_ref: owner_ref
      }) do
    if is_reference(timer_ref), do: Process.cancel_timer(timer_ref)
    if is_reference(owner_ref), do: Process.demonitor(owner_ref, [:flush])

    Enum.each(callback_workers, fn {_ref, pid} ->
      if Process.alive?(pid), do: Process.exit(pid, :kill)
    end)

    :ok
  end

  @spec parse_cron(String.t()) :: {:ok, Crontab.CronExpression.t()} | {:error, term()}
  defp parse_cron(cron_expr) do
    parse_attempts = parse_modes(cron_expr)

    Enum.reduce_while(parse_attempts, {:error, {:invalid_cron, cron_expr}}, fn extended, _acc ->
      case Parser.parse(cron_expr, extended) do
        {:ok, cron} -> {:halt, {:ok, cron}}
        {:error, reason} -> {:cont, {:error, {:invalid_cron, reason}}}
      end
    end)
  end

  @spec parse_modes(String.t()) :: [boolean()]
  defp parse_modes("@" <> _), do: [false]

  defp parse_modes(cron_expr) do
    count =
      cron_expr
      |> String.split(~r/\s+/, trim: true)
      |> length()

    if count > 5, do: [true, false], else: [false, true]
  end

  @spec schedule_next_tick(Crontab.CronExpression.t(), String.t()) ::
          {:ok, reference()} | {:error, term()}
  defp schedule_next_tick(cron, timezone) do
    with {:ok, now} <- now_in_timezone(timezone),
         {:ok, next_at} <- next_scheduled_at(cron, timezone, now),
         {:ok, delay_ms} <- timer_delay_ms(next_at, now) do
      {:ok, Process.send_after(self(), @tick, delay_ms)}
    end
  end

  @spec next_run_date(Crontab.CronExpression.t(), DateTime.t()) ::
          {:ok, NaiveDateTime.t()} | {:error, term()}
  defp next_run_date(cron, now) do
    try do
      case CronScheduler.get_next_run_date(cron, DateTime.to_naive(now)) do
        {:ok, next_naive} -> {:ok, next_naive}
        {:error, reason} -> {:error, {:next_run_not_found, reason}}
      end
    rescue
      e -> {:error, {:next_run_exception, Exception.message(e)}}
    end
  end

  @spec now_in_timezone(String.t()) :: {:ok, DateTime.t()} | {:error, term()}
  defp now_in_timezone(timezone) do
    case DateTime.now(timezone, @time_zone_database) do
      {:ok, now} -> {:ok, now}
      {:error, reason} -> {:error, {:invalid_timezone, reason}}
    end
  end

  @spec safe_execute((-> term())) :: :ok
  defp safe_execute(fun) do
    try do
      _ = fun.()
      :ok
    rescue
      error ->
        Logger.error("Scheduler callback raised: #{Exception.message(error)}")
        :ok
    catch
      kind, reason ->
        Logger.error("Scheduler callback #{kind}: #{inspect(reason)}")
        :ok
    end
  end

  @spec schedule_after_tick(state()) :: state()
  defp schedule_after_tick(%{cron: cron, timezone: timezone} = state) do
    case schedule_next_tick(cron, timezone) do
      {:ok, timer_ref} ->
        clear_retry(state, timer_ref)

      {:error, reason} ->
        enter_retry(state, reason)
    end
  end

  @spec retry_schedule(state()) :: state()
  defp retry_schedule(%{cron: cron, timezone: timezone} = state) do
    case schedule_next_tick(cron, timezone) do
      {:ok, timer_ref} ->
        clear_retry(state, timer_ref)

      {:error, reason} ->
        enter_retry(state, reason)
    end
  end

  @spec enter_retry(state(), term()) :: state()
  defp enter_retry(state, reason) do
    if not state.retrying? do
      Logger.warning(
        "Scheduler job entering retry mode for #{inspect(state.cron_expr)} after schedule failure: #{inspect(reason)}"
      )
    end

    timer_ref = Process.send_after(self(), @retry_schedule, @retry_delay_ms)
    %{state | timer_ref: timer_ref, retrying?: true}
  end

  @spec clear_retry(state(), reference()) :: state()
  defp clear_retry(state, timer_ref) do
    if state.retrying? do
      Logger.info("Scheduler job recovered schedule resolution for #{inspect(state.cron_expr)}")
    end

    %{state | timer_ref: timer_ref, retrying?: false}
  end

  @spec spawn_callback_worker(state()) :: state()
  defp spawn_callback_worker(%{fun: fun, callback_workers: callback_workers} = state) do
    {pid, ref} = spawn_monitor(fn -> safe_execute(fun) end)
    %{state | callback_workers: Map.put(callback_workers, ref, pid)}
  end

  @spec timer_delay_ms(DateTime.t(), DateTime.t()) :: {:ok, non_neg_integer()} | {:error, term()}
  defp timer_delay_ms(next_at, now) do
    delay_ms = DateTime.diff(next_at, now, :millisecond)

    if delay_ms >= 0 do
      {:ok, delay_ms}
    else
      {:error, {:invalid_next_schedule, delay_ms}}
    end
  end

  @spec do_next_scheduled_at(
          Crontab.CronExpression.t(),
          String.t(),
          DateTime.t(),
          non_neg_integer()
        ) ::
          {:ok, DateTime.t()} | {:error, term()}
  defp do_next_scheduled_at(_cron, _timezone, _from, 0), do: {:error, :schedule_resolution_limit}

  defp do_next_scheduled_at(cron, timezone, from, attempts_left) do
    with {:ok, next_naive} <- next_run_date(cron, from) do
      case DateTime.from_naive(next_naive, timezone, @time_zone_database) do
        {:ok, next_at} ->
          ensure_future_schedule(cron, timezone, next_at, from, attempts_left)

        {:ambiguous, _first, second} ->
          ensure_future_schedule(cron, timezone, second, from, attempts_left)

        {:gap, _before, after_dt} ->
          do_next_scheduled_at(cron, timezone, after_dt, attempts_left - 1)

        {:error, reason} ->
          {:error, {:invalid_timezone, reason}}
      end
    end
  end

  @spec ensure_future_schedule(
          Crontab.CronExpression.t(),
          String.t(),
          DateTime.t(),
          DateTime.t(),
          non_neg_integer()
        ) :: {:ok, DateTime.t()} | {:error, term()}
  defp ensure_future_schedule(cron, timezone, next_at, from, attempts_left) do
    case DateTime.compare(next_at, from) do
      :gt ->
        {:ok, next_at}

      _other ->
        with {:ok, next_from} <- advance_search_start(from, timezone) do
          do_next_scheduled_at(cron, timezone, next_from, attempts_left - 1)
        end
    end
  end

  @spec advance_search_start(DateTime.t(), String.t()) :: {:ok, DateTime.t()} | {:error, term()}
  defp advance_search_start(from, timezone) do
    with {:ok, utc_dt} <- DateTime.from_unix(DateTime.to_unix(from, :second) + 1, :second),
         {:ok, next_from} <- DateTime.shift_zone(utc_dt, timezone, @time_zone_database) do
      {:ok, next_from}
    else
      {:error, reason} -> {:error, {:invalid_timezone, reason}}
    end
  end
end

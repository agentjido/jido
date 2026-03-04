defmodule Jido.Scheduler.Job do
  @moduledoc false

  use GenServer

  require Logger

  alias Crontab.CronExpression.Parser
  alias Crontab.Scheduler, as: CronScheduler

  @tick :tick

  @type state :: %{
          fun: (-> term()),
          cron_expr: String.t(),
          cron: Crontab.CronExpression.t(),
          timezone: String.t(),
          timer_ref: reference() | nil
        }

  @spec start_link((-> term()), String.t(), String.t()) :: GenServer.on_start()
  def start_link(fun, cron_expr, timezone)
      when is_function(fun, 0) and is_binary(cron_expr) and is_binary(timezone) do
    GenServer.start_link(__MODULE__, %{fun: fun, cron_expr: cron_expr, timezone: timezone})
  end

  @impl true
  def init(%{fun: fun, cron_expr: cron_expr, timezone: timezone}) do
    ensure_time_zone_database()

    with {:ok, cron} <- parse_cron(cron_expr),
         {:ok, _now} <- now_in_timezone(timezone),
         {:ok, timer_ref} <- schedule_next_tick(cron, timezone) do
      {:ok,
       %{fun: fun, cron_expr: cron_expr, cron: cron, timezone: timezone, timer_ref: timer_ref}}
    else
      {:error, reason} ->
        {:stop, reason}
    end
  end

  @impl true
  def handle_info(@tick, %{fun: fun, cron: cron, timezone: timezone} = state) do
    execute(fun)

    case schedule_next_tick(cron, timezone) do
      {:ok, timer_ref} ->
        {:noreply, %{state | timer_ref: timer_ref}}

      {:error, reason} ->
        Logger.error(
          "Scheduler job stopping after schedule failure for #{inspect(state.cron_expr)}: #{inspect(reason)}"
        )

        {:stop, reason, %{state | timer_ref: nil}}
    end
  end

  def handle_info(_other, state), do: {:noreply, state}

  @impl true
  def terminate(_reason, %{timer_ref: timer_ref}) do
    if is_reference(timer_ref), do: Process.cancel_timer(timer_ref)
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
         {:ok, next_naive} <- next_run_date(cron, now),
         {:ok, next_local} <- resolve_local_datetime(next_naive, timezone) do
      delay_ms = max(DateTime.diff(next_local, now, :millisecond), 1)
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
    case DateTime.now(timezone) do
      {:ok, now} -> {:ok, now}
      {:error, reason} -> {:error, {:invalid_timezone, reason}}
    end
  end

  @spec resolve_local_datetime(NaiveDateTime.t(), String.t()) ::
          {:ok, DateTime.t()} | {:error, term()}
  defp resolve_local_datetime(naive, timezone) do
    case DateTime.from_naive(naive, timezone) do
      {:ok, datetime} ->
        {:ok, datetime}

      {:ambiguous, first, _second} ->
        {:ok, first}

      {:gap, _before, after_dt} ->
        {:ok, after_dt}

      {:error, reason} ->
        {:error, {:invalid_timezone, reason}}
    end
  end

  @spec execute((-> term())) :: :ok
  defp execute(fun) do
    Task.start(fn -> safe_execute(fun) end)
    :ok
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

  @spec ensure_time_zone_database() :: :ok
  defp ensure_time_zone_database do
    if Code.ensure_loaded?(Tzdata.TimeZoneDatabase) do
      Calendar.put_time_zone_database(Tzdata.TimeZoneDatabase)
    end

    :ok
  end
end

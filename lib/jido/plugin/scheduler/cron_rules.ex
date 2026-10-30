defmodule Jido.Plugin.Scheduler.CronRules do
  @moduledoc false

  alias Crontab.CronExpression.Parser

  @spec next_occurrence(String.t(), String.t(), DateTime.t()) ::
          {:ok, DateTime.t()} | {:error, term()}
  def next_occurrence(expression, timezone, %DateTime{} = after_time)
      when is_binary(expression) and is_binary(timezone) do
    extended? = length(String.split(expression)) > 5

    with {:ok, cron} <- Parser.parse(expression, extended?),
         {:ok, local_after} <- DateTime.shift_zone(after_time, timezone) do
      next_strict(cron, timezone, local_after, after_time)
    end
  rescue
    _exception -> {:error, :invalid_cron_boundary}
  catch
    _kind, _reason -> {:error, :invalid_cron_boundary}
  end

  def next_occurrence(_expression, _timezone, _after_time),
    do: {:error, :invalid_cron_boundary}

  defp next_local(cron, timezone, local_after) do
    case Crontab.Scheduler.get_next_run_date(cron, DateTime.to_naive(local_after)) do
      {:ok, naive_next} -> to_utc(cron, timezone, naive_next)
      {:error, _reason} = error -> error
    end
  end

  defp next_strict(cron, timezone, local_after, after_time) do
    with {:ok, next} <- next_local(cron, timezone, local_after) do
      if DateTime.compare(next, after_time) == :gt do
        {:ok, next}
      else
        next_local(cron, timezone, DateTime.add(local_after, 1, :microsecond))
      end
    end
  end

  defp to_utc(cron, timezone, naive_next) do
    case DateTime.from_naive(naive_next, timezone) do
      {:ok, next} -> DateTime.shift_zone(next, "Etc/UTC")
      {:ambiguous, _first, second} -> DateTime.shift_zone(second, "Etc/UTC")
      {:gap, _before, just_after} -> next_local(cron, timezone, just_after)
      {:error, _reason} = error -> error
    end
  end
end

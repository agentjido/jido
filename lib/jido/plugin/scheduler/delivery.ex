defmodule Jido.Plugin.Scheduler.Delivery do
  @moduledoc false
  alias Jido.AgentServer, as: Server
  alias Jido.Plugin.Scheduler
  alias Jido.Plugin.Scheduler.Durable
  alias Jido.Signal

  @type cursor :: :start | {:after, term()}
  @type outcome ::
          {:idle, cursor()}
          | {:delivered, cursor(), {:ok, term()}}
          | {:error, cursor(),
             {:state_read_failed, term()}
             | {:state_read_unavailable, term()}
             | {:invalid_scheduler_state, term()}
             | {:delivery_failed, term()}
             | {:delivery_unavailable, term()}}

  @spec attempt(Server.server(), cursor(), timeout()) :: outcome()
  def attempt(server, previous_job, timeout) do
    case read_state(server, timeout) do
      {:ok, %{cron: cron} = state} when is_map(cron) ->
        attempt_pending(server, state, previous_job, timeout)

      {:ok, state} ->
        {:error, previous_job, {:invalid_scheduler_state, state}}

      {:error, reason} ->
        {:error, previous_job, reason}
    end
  end

  defp attempt_pending(server, state, previous_job, timeout) do
    case next_entry(Durable.pending(state), previous_job) do
      nil ->
        {:idle, previous_job}

      {job, signal} ->
        deliver(server, job, signal, timeout)
    end
  end

  defp read_state(server, timeout) do
    case Server.plugin_state(server, Scheduler, timeout) do
      {:ok, state} -> {:ok, state}
      {:error, reason} -> {:error, {:state_read_failed, reason}}
    end
  catch
    :exit, reason -> {:error, {:state_read_unavailable, reason}}
  end

  defp next_entry(entries, cursor) do
    {first, next} =
      Enum.reduce(entries, {nil, nil}, fn {job, _signal} = entry, {first, next} ->
        first = earlier(first, entry)

        next =
          if after_cursor?(job, cursor),
            do: earlier(next, entry),
            else: next

        {first, next}
      end)

    next || first
  end

  defp earlier(nil, entry), do: entry
  defp earlier({job, _}, {candidate, _} = entry) when candidate < job, do: entry
  defp earlier(entry, _candidate), do: entry

  defp after_cursor?(_job, :start), do: false
  defp after_cursor?(job, {:after, previous_job}), do: job > previous_job

  defp deliver(server, job, signal, timeout) do
    fresh = signal |> Signal.to_map() |> Map.delete("id") |> Signal.new!()

    case Server.call(server, fresh, timeout) do
      {:ok, _value} = result -> {:delivered, {:after, job}, result}
      {:error, reason} -> {:error, {:after, job}, {:delivery_failed, reason}}
    end
  rescue
    error -> {:error, {:after, job}, {:delivery_unavailable, {:error, error}}}
  catch
    kind, reason -> {:error, {:after, job}, {:delivery_unavailable, {kind, reason}}}
  end
end

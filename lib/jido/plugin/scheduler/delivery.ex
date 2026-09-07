defmodule Jido.Plugin.Scheduler.Delivery do
  @moduledoc false
  alias Jido.AgentServer, as: Server
  alias Jido.Plugin.Scheduler
  alias Jido.Plugin.Scheduler.Durable
  alias Jido.Signal

  def attempt(server, previous_job, timeout) do
    with {:ok, state} <- Server.plugin_state(server, Scheduler, timeout),
         [_ | _] = entries <- state |> Durable.pending() |> Enum.sort() do
      {job, signal} = next_entry(entries, previous_job)
      {job, deliver(server, signal, timeout)}
    else
      _ -> {previous_job, :idle}
    end
  catch
    :exit, reason -> {previous_job, {:error, {:occurrence_delivery_unavailable, reason}}}
  end

  defp next_entry(entries, nil), do: hd(entries)

  defp next_entry(entries, previous_job) do
    Enum.find(entries, fn {job, _signal} -> job > previous_job end) || hd(entries)
  end

  defp deliver(server, signal, timeout) do
    fresh = signal |> Signal.to_map() |> Map.delete("id") |> Signal.new!()
    Server.call(server, fresh, timeout)
  catch
    :exit, reason -> {:error, {:occurrence_delivery_unavailable, reason}}
  end
end

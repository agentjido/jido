defmodule Jido.AgentServer.RegistryWorker do
  @moduledoc false

  @retry_interval 10
  @restart_wait 1_000

  def child_spec(opts) do
    opts
    |> Registry.child_spec()
    |> Map.put(:start, {__MODULE__, :start_link, [opts]})
  end

  def start_link(opts) do
    deadline = System.monotonic_time(:millisecond) + @restart_wait
    start_until_ready(opts, deadline)
  end

  defp start_until_ready(opts, deadline) do
    case Registry.start_link(opts) do
      {:ok, _pid} = started ->
        started

      {:error, _reason} = error ->
        if System.monotonic_time(:millisecond) < deadline do
          Process.sleep(@retry_interval)
          start_until_ready(opts, deadline)
        else
          error
        end
    end
  end
end

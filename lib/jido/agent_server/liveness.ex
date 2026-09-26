defmodule Jido.AgentServer.Liveness do
  @moduledoc false

  def check(pid, dead_reason) when is_pid(pid) do
    alive =
      if node(pid) == node(),
        do: Process.alive?(pid),
        else: :erpc.call(node(pid), Process, :alive?, [pid], 1_000)

    if alive, do: :ok, else: {:error, dead_reason}
  catch
    kind, reason -> {:error, {:liveness_unavailable, pid, {kind, reason}}}
  end

  def check(_pid, dead_reason), do: {:error, dead_reason}
end

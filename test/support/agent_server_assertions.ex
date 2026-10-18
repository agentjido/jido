defmodule JidoTest.AgentServerAssertions do
  @moduledoc false

  alias Jido.AgentServer

  # Use only at a test barrier where no commit can occur between the reads.
  def committed(server) do
    %{agent: AgentServer.agent(server), state_version: AgentServer.status(server).state_version}
  end

  def plugin(server, package) do
    case List.keyfind(
           Supervisor.which_children(AgentServer.activation(server)),
           {:plugin, package},
           0
         ) do
      {_, pid, _, _} when is_pid(pid) -> %{pid: pid}
      _ -> nil
    end
  end

  def replacement(activation, previous) do
    JidoTest.Eventually.eventually(fn ->
      case AgentServer.Supervisor.worker(activation) do
        pid when is_pid(pid) and pid != previous ->
          if AgentServer.await_ready(pid) == :ok, do: pid

        _ ->
          nil
      end
    end)
  end

  def start_agent(instance, agent, opts \\ []) do
    opts =
      if is_atom(agent), do: Keyword.put_new(opts, :id, Jido.Signal.ID.generate!()), else: opts

    with {:ok, server} <- Jido.start_agent(instance, agent, opts),
         :ok <- AgentServer.await_ready(server) do
      {:ok, server}
    end
  end

  def start_result(instance, agent, opts) do
    with {:ok, server} <- Jido.start_agent(instance, agent, opts) do
      monitor = Process.monitor(server)

      try do
        :ok = AgentServer.await_ready(server)
        Process.demonitor(monitor, [:flush])
        {:ok, server}
      catch
        :exit, _ ->
          receive do
            {:DOWN, ^monitor, :process, ^server, {:shutdown, reason}} -> {:error, reason}
          after
            5_000 -> raise "bootstrap did not stop"
          end
      end
    end
  end
end

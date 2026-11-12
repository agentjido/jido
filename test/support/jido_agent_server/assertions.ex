defmodule Jido.Test.AgentServer.Assertions do
  @moduledoc false

  alias Jido.AgentServer.Worker, as: AgentServer

  # Use only at a test barrier where no commit can occur between the reads.
  def committed(server) do
    snapshot = Jido.AgentServer.snapshot(server)
    %{agent: snapshot.agent, state_version: snapshot.agent_revision}
  end

  def plugin(server, package) do
    {_phase, data} = :sys.get_state(server)

    case List.keyfind(
           data.activation
           |> Jido.AgentServer.Supervisor.plugin_supervisor()
           |> Supervisor.which_children(),
           {:plugin, package},
           0
         ) do
      {_, pid, _, _} when is_pid(pid) -> %{pid: pid}
      _ -> nil
    end
  end

  def activation(server) do
    {_phase, data} = :sys.get_state(server)
    data.activation
  end

  def replacement(activation, previous, opts \\ []) do
    Jido.Test.Eventually.eventually(
      fn ->
        case Jido.AgentServer.Supervisor.worker(activation) do
          pid when is_pid(pid) and pid != previous ->
            if AgentServer.await_ready(pid) == :ok, do: pid

          _ ->
            nil
        end
      end,
      opts
    )
  end

  def start_agent(instance, agent, opts \\ []) do
    opts =
      if is_atom(agent), do: Keyword.put_new(opts, :id, Jido.Id.uuid7()), else: opts

    with {:ok, server} <- Jido.start_agent(instance, agent, opts),
         :ok <- AgentServer.await_ready(server) do
      {:ok, server}
    end
  end

  def start_result(instance, agent, opts) do
    with {:ok, server} <- Jido.start_agent(instance, agent, opts),
         :ok <- AgentServer.await_ready(server) do
      {:ok, server}
    end
  end
end

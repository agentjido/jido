defmodule Jido.Test.AgentServer.TopologyAssertions do
  @moduledoc false
  import ExUnit.Assertions
  alias Jido.AgentServer, as: Server

  def start_topology(jido, definition) do
    assert {:ok, server} = Jido.start_agent(jido, definition, id: Jido.Test.Case.unique_id())
    assert :ok = Server.await_ready(server)
    server
  end

  # Child tags are opaque. Tests select these example workers by domain labels.
  def members(server) do
    {_phase, data} = :sys.get_state(server)

    for {{:child, _tag}, %{root: root}} <-
          Jido.AgentServer.Supervisor.records(data.activation_state),
        pid = Jido.AgentServer.Supervisor.live_worker(root),
        is_pid(pid),
        do: pid
  end

  def labeled(server, label) do
    Enum.filter(members(server), &(Jido.AgentServer.snapshot(&1).agent.state.label == label))
  end

  def stop_topology(server) do
    {_phase, data} = :sys.get_state(server)
    monitors = monitor_runtime(data.activation)
    assert {:ok, _snapshot} = Server.stop(server)
    assert_down(monitors)
  end

  def monitor_runtime(supervisor) do
    for pid <- runtime(supervisor), do: {pid, Process.monitor(pid)}
  end

  def assert_down(monitors) do
    for {pid, ref} <- monitors, do: assert_receive({:DOWN, ^ref, :process, ^pid, _}, 5_000)
  end

  # Walk the owned tree through OTP APIs without depending on child IDs or state.
  defp runtime(supervisor) do
    [
      supervisor
      | Enum.flat_map(Supervisor.which_children(supervisor), fn
          {_, pid, :supervisor, _} when is_pid(pid) -> runtime(pid)
          {_, pid, :worker, _} when is_pid(pid) -> [pid]
          _ -> []
        end)
    ]
  end
end

defmodule JidoTest.TopologyAssertions do
  @moduledoc false
  import ExUnit.Assertions
  alias Jido.AgentServer

  # Observe only public Agent/Plugin children. OTP performs the shutdown.
  def monitor_runtime(agents, resources \\ []) do
    plugins =
      for agent <- agents,
          {_, %{kind: :plugin} = child} <- AgentServer.children(agent),
          pid <- [child.pid, child.lifecycle_pid],
          is_pid(pid),
          do: pid

    for pid <- Enum.uniq(agents ++ resources ++ plugins), do: {pid, Process.monitor(pid)}
  end

  def assert_down(monitors) do
    for {pid, ref} <- monitors, do: assert_receive({:DOWN, ^ref, :process, ^pid, _}, 5_000)
  end

  def stop_topology(controller, agents, resources \\ []) do
    monitors = monitor_runtime(agents, resources)
    assert :ok = Supervisor.stop(controller)
    assert_down(monitors)
  end
end

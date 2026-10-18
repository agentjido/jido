defmodule Jido.Examples.OTPSupervisionTest do
  use JidoTest.BasicSDKCase

  alias Jido.AgentServer, as: Server
  alias Jido.Examples.OTPSupervision.{Application, Counter}
  alias Jido.Examples.OTPSupervision.Jido, as: Runtime
  alias Jido.AgentServer.Supervisor, as: ServerSupervisor

  test "application supervision restores a commit and owns shutdown without a Topology", c do
    _isolated_case_instance = c.jido

    application =
      start_supervised!(%{
        id: Application,
        start: {Application, :start, [:normal, [jido: Runtime]]},
        type: :supervisor,
        restart: :temporary
      })

    assert [
             {:counter, activation, :supervisor, [ServerSupervisor]},
             {Runtime, infrastructure, :supervisor, [Jido]}
           ] = Supervisor.which_children(application)

    server = ServerSupervisor.worker(activation)
    assert Process.whereis(Runtime) == infrastructure
    assert :ok = Server.await_ready(server)
    assert Runtime.whereis_agent("otp-counter") == server
    assert Runtime.agent_count() == 1

    assert Server.activation(server) == activation

    {:ok, signal} = Counter.increment_signal(%{amount: 7})
    assert {:ok, committed, _directives} = Server.call(server, signal)
    assert committed.state.count == 7
    assert Server.snapshot(server).state_version == 1

    old_refs = monitor(children(activation))
    Process.exit(server, :kill)
    await_down(old_refs)
    eventually(fn -> is_pid(Runtime.whereis_agent("otp-counter")) end)
    replacement = Runtime.whereis_agent("otp-counter")
    assert replacement != server
    assert :ok = Server.await_ready(replacement)
    assert Server.agent(replacement) == committed
    assert Server.snapshot(replacement).state_version == 1
    # A clean stop stays stopped under :transient, even though its child spec
    # remains in the application supervisor.
    refs = monitor([activation | children(activation)])
    assert :ok = Runtime.stop_agent("otp-counter")
    await_down(refs)

    assert {:counter, :undefined, :supervisor, [ServerSupervisor]} =
             List.keyfind(Supervisor.which_children(application), :counter, 0)

    assert {:ok, new_activation} = Supervisor.restart_child(application, :counter)
    resumed = ServerSupervisor.worker(new_activation)
    assert :ok = Server.await_ready(resumed)
    assert Server.agent(resumed).state.count == 0

    refs = monitor([new_activation, infrastructure | children(new_activation)])
    assert :ok = Supervisor.stop(application)
    await_down(refs)
    assert Process.whereis(Runtime) == nil
  end

  defp children(root),
    do: for({_, pid, _, _} <- Supervisor.which_children(root), is_pid(pid), do: pid)

  defp monitor(pids), do: Enum.map(pids, &{Process.monitor(&1), &1})

  defp await_down(refs) do
    for {ref, pid} <- refs, do: assert_receive({:DOWN, ^ref, :process, ^pid, _}, 1_000)
  end
end

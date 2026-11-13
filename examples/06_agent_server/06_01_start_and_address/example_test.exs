Code.require_file("example.ex", __DIR__)
Code.require_file("application.ex", __DIR__)

defmodule Jido.Examples.OTPSupervisionTest do
  use Jido.Test.Agent.BasicSDKCase
  @moduletag :integration
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
    assert :ok = Jido.AgentServer.await_ready(server)
    assert Jido.whereis_agent(Runtime, "otp-counter") == server
    assert Jido.resident_agent_count(Runtime) == 1

    assert Jido.Test.AgentServer.ExampleRuntime.activation(server) == activation

    {:ok, signal} = Counter.increment_signal(%{amount: 7})

    (
      assert {:ok, %Jido.AgentServer.TurnResult{} = turn_result} =
               Jido.AgentServer.call(server, signal)

      assert turn_result.status in [:committed, :waiting]
      committed = Jido.AgentServer.snapshot(server).agent
    )

    assert committed.state.count == 7
    assert Jido.AgentServer.snapshot(server).agent_revision == 1

    old_refs = monitor([server])
    Process.exit(server, :kill)
    await_down(old_refs)
    eventually(fn -> is_pid(Jido.whereis_agent(Runtime, "otp-counter")) end)
    replacement = Jido.whereis_agent(Runtime, "otp-counter")
    assert replacement != server
    assert :ok = Jido.AgentServer.await_ready(replacement)
    assert Jido.AgentServer.snapshot(replacement).agent == committed
    assert Jido.AgentServer.snapshot(replacement).agent_revision == 1
    # A clean stop stays stopped under :transient, even though its child spec
    # remains in the application supervisor.
    refs = monitor([activation | children(activation)])
    assert :ok = Jido.stop_agent(Runtime, "otp-counter")
    await_down(refs)

    assert {:counter, :undefined, :supervisor, [ServerSupervisor]} =
             List.keyfind(Supervisor.which_children(application), :counter, 0)

    assert {:ok, new_activation} = Supervisor.restart_child(application, :counter)
    resumed = ServerSupervisor.worker(new_activation)
    assert :ok = Jido.AgentServer.await_ready(resumed)
    assert Jido.AgentServer.snapshot(resumed).agent.state.count == 0

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

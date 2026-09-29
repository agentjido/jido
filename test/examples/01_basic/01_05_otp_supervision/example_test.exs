defmodule Jido.Examples.OTPSupervisionTest do
  use JidoTest.BasicSDKCase

  alias Jido.AgentServer, as: Server
  alias Jido.Examples.OTPSupervision.{Application, Counter}
  alias Jido.Plugin.Scheduler

  test "application supervision restores a commit and owns shutdown without a Topology", c do
    jido = :"otp_example_#{c.jido}"

    application =
      start_supervised!(%{
        id: Application,
        start: {Application, :start, [:normal, [jido: jido]]},
        type: :supervisor,
        restart: :temporary
      })

    assert [{:counter, server, :worker, [Server]}, {^jido, infrastructure, :supervisor, [Jido]}] =
             Supervisor.which_children(application)

    assert Process.whereis(jido) == infrastructure
    assert :ok = Server.await_ready(server)
    assert Jido.whereis_agent(jido, "otp-counter") == server
    assert Jido.Topology.Controller.whereis(jido, "otp-counter") == nil

    plugin = Server.children(server)[{:plugin, Scheduler}]

    assert Enum.any?(DynamicSupervisor.which_children(Jido.agent_supervisor_name(jido)), fn
             {_, pid, _, _} -> pid == plugin.lifecycle_pid
           end)

    {:ok, signal} = Counter.increment_signal(%{amount: 7})
    assert {:ok, committed} = Server.call(server, signal)
    assert committed.state.count == 7
    assert Server.snapshot(server).state_version == 1

    old_refs = monitor([server, plugin.pid, plugin.lifecycle_pid])
    Process.exit(server, :kill)
    await_down(old_refs)
    eventually(fn -> is_pid(Jido.whereis_agent(jido, "otp-counter")) end)
    replacement = Jido.whereis_agent(jido, "otp-counter")
    assert replacement != server
    assert :ok = Server.await_ready(replacement)
    assert Server.agent(replacement) == committed
    assert Server.snapshot(replacement).state_version == 1
    runtime = Server.children(replacement)[{:plugin, Scheduler}]
    assert runtime.pid != plugin.pid

    # A clean stop stays stopped under :transient, even though its child spec
    # remains in the application supervisor.
    refs = monitor([replacement, runtime.pid, runtime.lifecycle_pid])
    assert :ok = Jido.stop_agent(jido, "otp-counter")
    await_down(refs)

    assert {:counter, :undefined, :worker, [Server]} =
             List.keyfind(Supervisor.which_children(application), :counter, 0)

    assert {:ok, resumed} = Supervisor.restart_child(application, :counter)
    assert :ok = Server.await_ready(resumed)
    assert Server.agent(resumed).state.count == 0

    runtime = Server.children(resumed)[{:plugin, Scheduler}]
    refs = monitor([resumed, runtime.pid, runtime.lifecycle_pid, infrastructure])
    assert :ok = Supervisor.stop(application)
    await_down(refs)
    assert Process.whereis(jido) == nil
  end

  defp monitor(pids), do: Enum.map(pids, &{Process.monitor(&1), &1})

  defp await_down(refs) do
    for {ref, pid} <- refs, do: assert_receive({:DOWN, ^ref, :process, ^pid, _}, 1_000)
  end
end

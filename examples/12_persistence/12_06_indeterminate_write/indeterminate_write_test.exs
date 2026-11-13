Code.require_file("indeterminate_store.ex", __DIR__)
Code.require_file("indeterminate_write_probe.ex", __DIR__)

defmodule Jido.Examples.Persistence.IndeterminateWriteTest do
  use ExUnit.Case, async: true
  @moduletag :integration

  alias Jido.Examples.Persistence.IndeterminateWrite, as: Probe
  alias Jido.Examples.Persistence.IndeterminateStore
  alias Jido.Persistence

  setup do
    suffix = System.unique_integer([:positive])
    jido = :"indeterminate_write_#{suffix}"
    store_pid = start_supervised!(IndeterminateStore)
    persistence = {IndeterminateStore, store: store_pid, fault_revision: 2}

    start_supervised!(
      {Jido, name: jido, namespace: "examples/persistence/indeterminate-write/#{suffix}", persistence: persistence},
      id: jido
    )

    %{jido: jido, persistence: persistence}
  end

  test "an uncertain stored write requires reconciliation before cleanup", %{
    jido: jido,
    persistence: persistence
  } do
    id = "example-indeterminate-write"
    context = %{}

    assert {:ok, server} =
             Jido.start_agent(jido, Probe,
               id: id,
               persistence: :inherit,
               persistence_mode: :create,
               default_dispatch: {:pid, target: self()}
             )

    assert :ok = Jido.AgentServer.await_ready(server)

    {:ok, route_signal_1} = Probe.increment_signal(%{request_id: "first", amount: 1})

    assert {:ok,
            %Jido.AgentServer.TurnResult{
              status: :uncertain,
              durability: :unknown,
              error: :indeterminate
            }} =
             Jido.AgentServer.call(server, route_signal_1, context: context)

    assert %{work_state: :faulted, admission: :blocked} = Jido.AgentServer.status(server)
    assert Jido.whereis_agent(jido, id) == server

    assert {:ok, %{state: %{count: 1}}, 2} =
             Persistence.load_agent_with_revision(persistence, Probe, id, instance: jido)

    refute_received {:signal, %{type: "examples.persistence.indeterminate_write.applied"}}
    assert {:error, :reconciliation_required} = next_command(server, context)
    assert Jido.resident_agent_count(jido) == 1

    assert {:error, :unsafe_resume} = Jido.stop_agent(jido, server)

    old_monitor = Process.monitor(server)
    assert {:ok, ref} = Jido.agent_ref(jido, id)
    assert {:ok, replacement} = Jido.reconcile_agent(jido, ref)
    assert_receive {:DOWN, ^old_monitor, :process, ^server, _reason}, 1_000
    assert replacement != server
    assert :ok = Jido.AgentServer.await_ready(replacement)
    assert Jido.AgentServer.snapshot(replacement).agent.state.count == 1

    assert :ok = Jido.stop_agent(jido, replacement)
    assert Jido.resident_agent_count(jido) == 0
  end

  defp next_command(server, context) do
    {:ok, route_signal_2} = Probe.increment_signal(%{request_id: "second", amount: 10})
    Jido.AgentServer.call(server, route_signal_2, context: context)
  catch
    :exit, reason -> {:error, reason}
  end
end

Code.require_file("indeterminate_write_probe.ex", __DIR__)

defmodule Jido.Examples.Persistence.IndeterminateWriteTest do
  use Jido.Test.Case, async: true
  @moduletag :integration

  alias Jido.Examples.Persistence.IndeterminateWrite, as: Probe
  alias Jido.Persistence
  alias Jido.Test.Persistence.ProbeStore

  test "an uncertain stored write blocks output and later evaluation on stale state", %{
    jido: jido
  } do
    store = {ProbeStore, store: start_supervised!(ProbeStore)}
    {ProbeStore, opts} = store
    id = unique_id("example-indeterminate-write")
    context = %{}

    assert {:ok, server} =
             Jido.Test.AgentServer.ExampleRuntime.start_agent(jido, Probe,
               id: id,
               persistence:
                 {ProbeStore,
                  opts
                  |> Keyword.put(:write_result, :indeterminate)
                  |> Keyword.put(:fault_revision, 2)},
               persistence_mode: :create,
               default_dispatch: {:pid, target: self()}
             )

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
             Persistence.load_agent_with_revision(store, Probe, id, instance: jido)

    refute_received {:signal, %{type: "examples.persistence.indeterminate_write.applied"}}
    assert {:error, :reconciliation_required} = next_command(server, context)
    assert Jido.resident_agent_count(jido) == 1
  end

  defp next_command(server, context) do
    {:ok, route_signal_2} = Probe.increment_signal(%{request_id: "second", amount: 10})
    Jido.AgentServer.call(server, route_signal_2, context: context)
  catch
    :exit, reason -> {:error, reason}
  end
end

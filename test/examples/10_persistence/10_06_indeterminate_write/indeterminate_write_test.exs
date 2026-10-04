defmodule JidoTest.Examples.Persistence.IndeterminateWriteTest do
  use JidoTest.Case, async: true

  @moduletag :example

  alias Jido.Examples.Persistence.IndeterminateWrite, as: Probe
  alias Jido.Persistence
  alias JidoTest.Persistence.ProbeStore

  test "an uncertain stored write blocks output and later evaluation on stale state", %{
    jido: jido
  } do
    store = {ProbeStore, store: start_supervised!(ProbeStore)}
    {ProbeStore, opts} = store
    id = unique_id("example-indeterminate-write")
    observer = self()
    context = %{reply_to: observer}

    assert {:ok, server} =
             Jido.start_agent(jido, Probe,
               id: id,
               persistence: {ProbeStore, Keyword.put(opts, :write_result, :indeterminate)},
               restore: false
             )

    {:ok, route_signal_1} = Probe.increment_signal(%{request_id: "first", amount: 1})

    assert {:error, {:persistence_failed, :indeterminate}} =
             Jido.AgentServer.call(server, route_signal_1, context: context)

    assert {:ok, %{state: %{count: 1}}, 1} =
             Persistence.load_agent_with_revision(store, Probe, id, instance: jido)

    refute_received {:signal, %{type: "examples.persistence.indeterminate_write.applied"}}
    assert match?({:error, _}, next_command(server, context))
  end

  defp next_command(server, context) do
    {:ok, route_signal_2} = Probe.increment_signal(%{request_id: "second", amount: 10})
    Jido.AgentServer.call(server, route_signal_2, context: context)
  catch
    :exit, reason -> {:error, reason}
  end
end

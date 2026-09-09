defmodule JidoTest.Examples.IndeterminateWriteTest do
  use JidoTest.Case, async: true

  @moduletag :example

  alias Jido.Examples.IndeterminateWriteProbe, as: Probe
  alias Jido.Examples.PersistenceProbeStore
  alias Jido.Persistence

  test "an uncertain stored write blocks output and later evaluation on stale state", %{
    jido: jido
  } do
    store = {PersistenceProbeStore, store: start_supervised!(PersistenceProbeStore)}
    {PersistenceProbeStore, opts} = store
    id = unique_id("example-indeterminate-write")
    observer = self()
    context = %{reply_to: observer, on_execute: &send(observer, {:evaluated, &1})}

    assert {:ok, server} =
             Jido.start_agent(jido, Probe,
               id: id,
               persistence:
                 {PersistenceProbeStore, Keyword.put(opts, :write_result, :indeterminate)},
               restore: false
             )

    assert {:error, {:persistence_failed, :indeterminate}} =
             Probe.increment(server, "first", 1, context: context)

    assert_receive {:evaluated, "first"}

    assert {:ok, %{state: %{count: 1}}, 1} =
             Persistence.load_agent_with_revision(store, Probe, id, instance: jido)

    refute_received {:signal, %{type: "persistence.probe.applied"}}
    assert match?({:error, _}, next_command(server, context))
    refute_received {:evaluated, "second"}
  end

  defp next_command(server, context) do
    Probe.increment(server, "second", 10, context: context)
  catch
    :exit, reason -> {:error, reason}
  end
end

Code.require_file("../../support/loader.exs", __DIR__)

alias Jido.Test.Examples.Loader
Loader.require_source!("13_persistence/13_06_indeterminate_write/indeterminate_write_probe.ex")

defmodule Jido.Examples.Persistence.IndeterminateWriteTest do
  use Jido.Test.Case, async: true
  @moduletag :example

  setup_all do
    Jido.Test.Examples.Loader.require_source!("13_persistence/13_06_indeterminate_write/indeterminate_write_probe.ex")

    :ok
  end

  alias Jido.Examples.Persistence.IndeterminateWrite, as: Probe
  alias Jido.Persistence
  alias Jido.Test.Persistence.ProbeStore

  test "an uncertain stored write blocks output and later evaluation on stale state", %{
    jido: jido
  } do
    store = {ProbeStore, store: start_supervised!(ProbeStore)}
    {ProbeStore, opts} = store
    id = unique_id("example-indeterminate-write")
    observer = self()
    context = %{reply_to: observer}

    assert {:ok, server} =
             Jido.Test.AgentServer.ExampleRuntime.start_agent(jido, Probe,
               id: id,
               persistence: {ProbeStore, Keyword.put(opts, :write_result, :indeterminate)},
               persistence_mode: :create
             )

    monitor = Process.monitor(server)

    {:ok, route_signal_1} = Probe.increment_signal(%{request_id: "first", amount: 1})

    assert {:error, %Jido.Error.ExecutionError{details: %{reason: :indeterminate}}} =
             Jido.AgentServer.call(server, route_signal_1, context: context)

    assert_receive {:DOWN, ^monitor, :process, ^server, _reason}, 1_000
    assert Jido.whereis_agent(jido, id) == nil

    assert {:ok, %{state: %{count: 1}}, 1} =
             Persistence.load_agent_with_revision(store, Probe, id, instance: jido)

    refute_received {:signal, %{type: "examples.persistence.indeterminate_write.applied"}}
    assert match?({:error, _}, next_command(server, context))
    assert Jido.agent_count(jido) == 0
  end

  defp next_command(server, context) do
    {:ok, route_signal_2} = Probe.increment_signal(%{request_id: "second", amount: 10})
    Jido.AgentServer.call(server, route_signal_2, context: context)
  catch
    :exit, reason -> {:error, reason}
  end
end

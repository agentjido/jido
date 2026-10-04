defmodule JidoTest.Persistence.IndeterminateWriteTest do
  use JidoTest.Case, async: true
  @moduletag :research
  @moduletag capability: "PERSIST-03"

  alias Jido.AgentServer, as: Server
  alias Jido.Persistence
  alias JidoTest.Persistence.IndeterminateWriteProbe, as: Probe
  alias JidoTest.Persistence.ProbeStore, as: Store

  defmodule LostReply do
    @behaviour Jido.Persistence.Adapter
    defdelegate get(key, opts), to: Store
    defdelegate put(key, value, opts), to: Store
    defdelegate delete(key, opts), to: Store

    def compare_and_swap(key, expected, value, opts) do
      :ok = Store.compare_and_swap(key, expected, value, Keyword.put(opts, :write_result, :ok))

      if :erlang.binary_to_term(value, [:safe]).revision == 0 do
        :ok
      else
        raise "stored write reply lost"
      end
    end
  end

  setup do
    observer = self()

    {:ok,
     store: {Store, store: start_supervised!(Store)},
     id: unique_id("indeterminate-write"),
     turn_context: %{reply_to: observer}}
  end

  test "a confirmed write commits state and permits post-commit output", c do
    {:ok, pid} = start_agent(c, :ok)

    {:ok, route_signal_1} = Probe.increment_signal(%{request_id: "first", amount: 1})

    assert {:ok, agent} =
             Jido.AgentServer.call(pid, route_signal_1, context: c.turn_context)

    assert_receive {:signal,
                    %{
                      type: "test.persistence.indeterminate_write.applied",
                      data: %{count: 1}
                    }}

    assert Server.snapshot(pid) == %{agent: agent, state_version: 1}

    assert {:ok, ^agent, 1} =
             Persistence.load_agent_with_revision(c.store, Probe, c.id, instance: c.jido)
  end

  test "an uncertain reply can follow a stored write without dispatching its Directive", c do
    {:ok, pid} = start_agent(c, :indeterminate)

    {:ok, route_signal_2} = Probe.increment_signal(%{request_id: "first", amount: 1})

    assert {:error, {:persistence_failed, :indeterminate}} =
             Jido.AgentServer.call(pid, route_signal_2, context: c.turn_context)

    assert_stored_first(c)
    refute_received {:signal, %{type: "test.persistence.indeterminate_write.applied"}}
  end

  test "an indeterminate write prevents evaluation of the next Action on stale state", c do
    {:ok, pid} = start_agent(c, :indeterminate)

    {:ok, route_signal_3} = Probe.increment_signal(%{request_id: "first", amount: 1})

    assert {:error, {:persistence_failed, :indeterminate}} =
             Jido.AgentServer.call(pid, route_signal_3, context: c.turn_context)

    assert_stored_first(c)

    # A stopped Server or a rejected command can satisfy the admission boundary.
    # Do not install a stopping error policy: this test requires a core guarantee.
    result = try_next_command(pid, c.turn_context)
    assert match?({:error, _}, result) or match?({:exit, _}, result)
    refute_received {:signal, %{type: "test.persistence.indeterminate_write.applied"}}
    assert_stored_first(c)
  end

  test "a raised callback after storage also prevents later Action evaluation", c do
    {_store, opts} = c.store

    assert {:ok, pid} =
             Jido.start_agent(c.jido, Probe,
               id: c.id,
               persistence: {LostReply, opts},
               restore: false
             )

    {:ok, route_signal_4} = Probe.increment_signal(%{request_id: "first", amount: 1})

    assert {:error, {:persistence_failed, {:indeterminate, %Jido.Error.ExecutionError{}}}} =
             Jido.AgentServer.call(pid, route_signal_4, context: c.turn_context)

    assert_stored_first(c)
    result = try_next_command(pid, c.turn_context)
    assert match?({:error, _}, result) or match?({:exit, _}, result)
    refute_received {:signal, %{type: "test.persistence.indeterminate_write.applied"}}
  end

  defp start_agent(c, write_result) do
    {Store, opts} = c.store

    Jido.start_agent(c.jido, Probe,
      id: c.id,
      persistence: {Store, Keyword.put(opts, :write_result, write_result)},
      restore: false
    )
  end

  defp assert_stored_first(c) do
    assert {:ok, %{state: %{count: 1}}, 1} =
             Persistence.load_agent_with_revision(c.store, Probe, c.id, instance: c.jido)
  end

  defp try_next_command(pid, context) do
    {:ok, route_signal_5} = Probe.increment_signal(%{request_id: "second", amount: 10})
    Jido.AgentServer.call(pid, route_signal_5, context: context)
  catch
    :exit, reason -> {:exit, reason}
  end
end

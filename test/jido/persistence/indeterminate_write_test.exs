defmodule Jido.Persistence.IndeterminateWriteTest do
  use Jido.Test.Case, async: true
  @moduletag :research
  @moduletag capability: "PERSIST-03"

  alias Jido.Persistence
  alias Jido.AgentServer.TurnResult
  alias Jido.Test.Persistence.IndeterminateWriteProbe, as: Probe
  alias Jido.Test.Persistence.ProbeStore, as: Store

  defmodule LostReply do
    @behaviour Jido.Persistence.Store
    defdelegate validate_options(opts), to: Store
    defdelegate get(key, opts), to: Store
    defdelegate put(key, value, opts), to: Store
    defdelegate delete(key, opts), to: Store

    def compare_and_swap(key, expected, value, opts) do
      :ok = Store.compare_and_swap(key, expected, value, Keyword.put(opts, :write_result, :ok))

      case decode_term(value) do
        %{rev: 2} -> raise "stored write reply lost"
        _other -> :ok
      end
    end

    defp decode_term(value) do
      case Jido.Persistence.Codec.Term.decode(value, []) do
        {:ok, decoded} -> decoded
        {:error, _reason} -> :not_an_external_term
      end
    end
  end

  setup do
    observer = Module.concat(__MODULE__, "Observer#{System.unique_integer([:positive])}")
    Process.register(self(), observer)

    {:ok,
     store: {Store, store: start_supervised!(Store)},
     id: unique_id("indeterminate-write"),
     observer: observer,
     turn_context: %{emit_reply: true}}
  end

  test "a confirmed write commits state and permits post-commit output", c do
    {jido, pid} = start_agent(c, :ok)

    {:ok, route_signal_1} = Probe.increment_signal(%{request_id: "first", amount: 1})

    assert {:ok, %TurnResult{status: :committed, durability: :durable}} =
             Jido.AgentServer.call(pid, route_signal_1, context: c.turn_context)

    # The commit reply precedes asynchronous Directive dispatch.
    assert_receive {:signal,
                    %{
                      type: "test.persistence.indeterminate_write.applied",
                      data: %{count: 1}
                    }},
                   5_000

    snapshot = Jido.AgentServer.snapshot(pid)
    agent = snapshot.agent
    assert snapshot.agent_revision == 1
    assert snapshot.persistence_revision == 2

    assert {:ok, ^agent, 2} =
             Persistence.load_agent_with_revision(c.store, Probe, c.id, instance: jido)
  end

  test "an uncertain reply can follow a stored write without dispatching its Directive", c do
    {jido, pid} = start_agent(c, :indeterminate)

    {:ok, route_signal_2} = Probe.increment_signal(%{request_id: "first", amount: 1})

    assert {:ok,
            %TurnResult{
              status: :uncertain,
              durability: :unknown,
              error: :indeterminate
            }} =
             Jido.AgentServer.call(pid, route_signal_2, context: c.turn_context)

    assert_stored_first(c, jido)
    refute_received {:signal, %{type: "test.persistence.indeterminate_write.applied"}}
  end

  test "an indeterminate write prevents evaluation of the next Action on stale state", c do
    {jido, pid} = start_agent(c, :indeterminate)

    {:ok, route_signal_3} = Probe.increment_signal(%{request_id: "first", amount: 1})

    assert {:ok,
            %TurnResult{
              status: :uncertain,
              durability: :unknown,
              error: :indeterminate
            }} =
             Jido.AgentServer.call(pid, route_signal_3, context: c.turn_context)

    assert_stored_first(c, jido)

    assert try_next_command(pid, c.turn_context) == {:error, :reconciliation_required}
    refute_received {:signal, %{type: "test.persistence.indeterminate_write.applied"}}
    assert_stored_first(c, jido)
  end

  test "a raised callback after storage also prevents later Action evaluation", c do
    {_store, opts} = c.store
    persistence = {LostReply, opts}
    jido = persistent_instance(persistence)

    assert {:ok, pid} =
             Jido.Test.AgentServer.Assertions.start_agent(jido, Probe,
               id: c.id,
               persistence_mode: :create,
               default_dispatch: {:pid, target: self()}
             )

    {:ok, route_signal_4} = Probe.increment_signal(%{request_id: "first", amount: 1})

    assert {:ok,
            %TurnResult{
              status: :uncertain,
              durability: :unknown,
              error: {:indeterminate, %Jido.Error.ExecutionError{}}
            }} =
             Jido.AgentServer.call(pid, route_signal_4, context: c.turn_context)

    assert_stored_first(c, jido)
    assert try_next_command(pid, c.turn_context) == {:error, :reconciliation_required}
    refute_received {:signal, %{type: "test.persistence.indeterminate_write.applied"}}
  end

  defp start_agent(c, write_result) do
    {Store, opts} = c.store

    persistence =
      {Store, opts |> Keyword.put(:write_result, write_result) |> Keyword.put(:fault_revision, 2)}

    jido = persistent_instance(persistence)

    {:ok, pid} =
      Jido.Test.AgentServer.Assertions.start_agent(jido, Probe,
        id: c.id,
        persistence_mode: :create,
        default_dispatch: {:pid, target: self()}
      )

    {jido, pid}
  end

  defp assert_stored_first(c, jido) do
    assert {:ok, %{state: %{count: 1}}, 2} =
             Persistence.load_agent_with_revision(c.store, Probe, c.id, instance: jido)
  end

  defp persistent_instance(persistence) do
    id = System.unique_integer([:positive])
    name = :"indeterminate_persistence_#{id}"

    start_supervised!(
      {Jido, name: name, namespace: "test/indeterminate/#{id}", persistence: persistence},
      id: {Jido, name}
    )

    name
  end

  defp try_next_command(pid, context) do
    {:ok, route_signal_5} = Probe.increment_signal(%{request_id: "second", amount: 10})
    Jido.AgentServer.call(pid, route_signal_5, context: context)
  catch
    :exit, reason -> {:exit, reason}
  end
end

defmodule JidoTest.AgentServer.DurableTurn.CheckpointStoreTest do
  use JidoTest.Case, async: true
  use Covenant.Case, component: "jido.agent_server.durable_turn", async: true

  alias Jido.AgentServer.DurableTurn.CheckpointStore, as: Store
  alias Jido.AgentServer.DurableTurn.JoinCompletedRef
  alias JidoTest.DurableFixtures, as: F

  defmodule Increment do
    use Jido.Action, name: "checkpoint_hydration_increment"

    @impl true
    def run(%{value: value}, _context), do: {:ok, %{value: value + 1}}
  end

  defmodule HydrationFlow do
    use Jido.Flow, name: "checkpoint_hydration_flow"

    flow do
      step "one", action: Increment, params: %{value: input(:value)}
      step "two", action: Increment, params: %{value: result("one", :value)}
      output result("two")
    end
  end

  defmodule BatchFlow do
    use Jido.Flow, name: "checkpoint_batch_flow"

    flow do
      map "items", collection: input(:items), action: Increment, params: %{value: item()}
      output %{items: result("items")}
    end
  end

  defmodule Bytes do
    @behaviour Jido.Persistence.Adapter

    def get(key, opts) do
      Agent.get(opts[:store], fn records ->
        case Map.fetch(records, key) do
          {:ok, bytes} -> {:ok, bytes, token(bytes)}
          :error -> {:error, :not_found}
        end
      end)
    end

    def compare_and_swap(key, expected, bytes, opts) do
      Agent.get_and_update(opts[:store], fn records ->
        stored = Map.get(records, key, :not_found)

        matches? =
          case expected do
            {:token, expected} when is_binary(stored) -> token(stored) == expected
            _ -> stored == expected
          end

        if matches?,
          do: {:ok, Map.put(records, key, bytes)},
          else: {{:error, :conflict}, records}
      end)
    end

    defp token(bytes), do: :crypto.hash(:sha256, bytes)

    def delete(key, opts) do
      if owner = opts[:delete_owner] do
        first? = is_nil(Process.get(:checkpoint_delete_started))
        Process.put(:checkpoint_delete_started, true)

        if first? do
          send(owner, {:checkpoint_delete_started, self(), key})

          receive do
            {:continue_checkpoint_delete, ^key} -> :ok
          end
        end
      end

      Agent.update(opts[:store], &Map.delete(&1, key))
    end
  end

  defmodule BarrierBytes do
    @behaviour Jido.Persistence.Adapter
    alias JidoTest.AgentServer.DurableTurn.CheckpointStoreTest.Bytes

    def get(key, opts), do: Bytes.get(key, opts)
    def delete(key, opts), do: Bytes.delete(key, opts)

    def compare_and_swap(key, expected, bytes, opts) do
      stage = Keyword.fetch!(opts, :barrier_stage)

      if barrier_key?(stage, key) and is_nil(Process.get({__MODULE__, stage})) do
        Process.put({__MODULE__, stage}, true)
        owner = Keyword.fetch!(opts, :barrier_owner)
        send(owner, {:fact_cas_ready, stage, self(), key})

        receive do
          {:continue_fact_cas, ^stage, ^key} -> :ok
        end
      end

      Bytes.compare_and_swap(key, expected, bytes, opts)
    end

    defp barrier_key?(:index, key), do: String.ends_with?(key, ":facts:index")

    defp barrier_key?(:fact, key) do
      String.contains?(key, ":facts:") and
        not String.ends_with?(key, ":facts:head") and
        not String.ends_with?(key, ":facts:index")
    end
  end

  setup c do
    store = start_supervised!({Agent, fn -> %{} end})
    config = {Bytes, store: store}
    init = %{jido: c.jido, partition: "north", agent_id: "worker"}
    id = identity(init, "job")
    assert :ok = Store.register(c.jido, id, config)
    %{store: store, config: config, init: init, id: id}
  end

  @tag obligation: "jido.agent_server.durable_turn.I2"
  test "Runic appends each event batch once and streams committed events in order", c do
    assert Runic.Runner.Store.supports_stream?(Jido.AgentServer.Store)
    assert {:error, :not_found} = Store.stream(c.id, c.jido)

    first = [%{event: 1}, %{event: 2}]
    second = [%{event: 3}]
    assert {:ok, 1} = Store.append(c.id, first, c.jido)
    assert {:ok, 2} = Store.append(c.id, second, c.jido)
    assert {:ok, events} = Store.stream(c.id, c.jido)
    assert Enum.to_list(events) == first ++ second

    records = Agent.get(c.store, &Map.values/1)
    assert length(records) == 3

    decoded = Enum.map(records, &:erlang.binary_to_term/1)
    assert Enum.count(decoded, &(&1 == 2)) == 1
    assert Enum.count(decoded, &is_list/1) == 2

    assert Enum.sort(Enum.filter(decoded, &is_list/1)) ==
             Enum.sort([first, second])
  end

  @tag obligation: "jido.agent_server.durable_turn.I2"
  test "repairs a tail chunk before the next append", c do
    assert {:ok, 1} = Store.append(c.id, [:first], c.jido)

    count_key =
      Agent.get(c.store, fn records ->
        records |> Map.keys() |> Enum.find(&(not String.contains?(&1, ":batches:")))
      end)

    Agent.update(c.store, &Map.delete(&1, count_key))

    assert {:ok, 2} = Store.append(c.id, [:second], c.jido)
    assert {:ok, [:first, :second]} = Store.stream(c.id, c.jido)
  end

  @tag obligation: "jido.agent_server.durable_turn.I2"
  test "stores cumulative frame facts as bounded references and restores exact values", c do
    session = large_session()
    root = Jido.Exec.Frame.new(%{session: session})

    assert :ok = Store.save_fact(c.id, :root, root, c.jido)

    {last, full_bytes} =
      Enum.reduce(1..8, {root, encoded_bytes(root)}, fn step, {parent, total} ->
        child =
          Jido.Exec.Frame.put_result(
            parent,
            "step_#{step}",
            %{session: session, output: step},
            []
          )

        hash = {:fact, step}
        assert :ok = Store.save_fact(c.id, hash, child, c.jido)
        assert {:ok, ^child} = Store.load_fact(c.id, hash, c.jido)
        {child, total + encoded_bytes(child)}
      end)

    assert {:ok, ^last} = Store.load_fact(c.id, {:fact, 8}, c.jido)

    stored_fact_bytes =
      Agent.get(c.store, fn records ->
        for {key, bytes} <- records,
            String.contains?(key, ":facts:"),
            not String.ends_with?(key, ":head"),
            reduce: 0 do
          total -> total + byte_size(bytes)
        end
      end)

    assert stored_fact_bytes < div(full_bytes, 10)
  end

  @tag obligation: "jido.agent_server.durable_turn.I2"
  test "rejects a conflicting value for one fact identity", c do
    assert :ok = Store.save_fact(c.id, :same, %{value: 1}, c.jido)
    assert :ok = Store.save_fact(c.id, :same, %{value: 1}, c.jido)

    assert {:error, :fact_value_conflict} =
             Store.save_fact(c.id, :same, %{value: 2}, c.jido)

    assert {:ok, %{value: 1}} = Store.load_fact(c.id, :same, c.jido)
  end

  @tag obligation: "jido.agent_server.durable_turn.I2"
  test "retries a concurrent fact index update", c do
    use_barrier_store(c, :index)

    left = Task.async(fn -> Store.save_fact(c.id, :left, %{value: 1}, c.jido) end)
    right = Task.async(fn -> Store.save_fact(c.id, :right, %{value: 2}, c.jido) end)

    release_fact_barrier(:index, 2)

    assert :ok = Task.await(left)
    assert :ok = Task.await(right)
    assert {:ok, %{value: 1}} = Store.load_fact(c.id, :left, c.jido)
    assert {:ok, %{value: 2}} = Store.load_fact(c.id, :right, c.jido)
  end

  @tag obligation: "jido.agent_server.durable_turn.I2"
  test "accepts concurrent idempotent writes for one fact", c do
    use_barrier_store(c, :fact)
    value = %{value: large_session()}

    left = Task.async(fn -> Store.save_fact(c.id, :same, value, c.jido) end)
    right = Task.async(fn -> Store.save_fact(c.id, :same, value, c.jido) end)

    release_fact_barrier(:fact, 2)

    assert :ok = Task.await(left)
    assert :ok = Task.await(right)
    assert {:ok, ^value} = Store.load_fact(c.id, :same, c.jido)
  end

  @tag obligation: "jido.agent_server.durable_turn.I2"
  test "rejects a fact value that does not match its stored digest", c do
    assert :ok = Store.save_fact(c.id, :checked, %{value: 1}, c.jido)

    {key, record} =
      Agent.get(c.store, fn records ->
        Enum.find_value(records, fn {key, bytes} ->
          case :erlang.binary_to_term(bytes) do
            {:jido_fact_value, 1, 0, digest, :full, %{value: 1}} ->
              {key, {:jido_fact_value, 1, 0, digest, :full, %{value: 2}}}

            _other ->
              nil
          end
        end)
      end)

    Agent.update(c.store, &Map.put(&1, key, :erlang.term_to_binary(record, [:deterministic])))

    assert {:error, :invalid_execution_checkpoint} = Store.load_fact(c.id, :checked, c.jido)
  end

  @tag obligation: "jido.agent_server.durable_turn.I2"
  test "stores a JoinCompleted result as a fact reference", c do
    value = [Jido.Exec.Frame.new(%{session: large_session()})]

    event = %Runic.Workflow.Events.JoinCompleted{
      join_hash: :join,
      result_fact_hash: :joined,
      result_value: value,
      result_ancestry: {:join, :parent},
      contribution_fact_hashes: [:left, :right],
      weight: 2
    }

    assert {:ok, 1} = Store.append(c.id, [event], c.jido)

    stored_events =
      Agent.get(c.store, fn records ->
        records
        |> Map.values()
        |> Enum.map(&:erlang.binary_to_term/1)
        |> Enum.find(&is_list/1)
      end)

    assert [%{event | result_value: nil}] == stored_events

    assert {:ok,
            [
              %JoinCompletedRef{
                join_hash: :join,
                result_fact_hash: :joined,
                result_ancestry: {:join, :parent},
                contribution_fact_hashes: [:left, :right],
                weight: 2
              }
            ]} = Store.stream(c.id, c.jido)

    assert {:ok, ^value} = Store.load_fact(c.id, :joined, c.jido)
  end

  @tag obligation: "jido.agent_server.durable_turn.I2"
  test "checkpoint keys use the stable unpadded encoding", c do
    id = {:jido_execution, "n", "p", "a", "t"}
    assert :ok = Store.register(c.jido, id, c.config)
    assert {:ok, 1} = Store.append(id, [:event], c.jido)

    expected =
      "jido:execution:" <>
        Base.url_encode64(:erlang.term_to_binary(id), padding: false)

    assert expected in Agent.get(c.store, &Map.keys/1)
  end

  @tag obligation: "jido.agent_server.durable_turn.I2"
  test "rejects an invalid batch count", c do
    key =
      "jido:execution:" <>
        Base.url_encode64(:erlang.term_to_binary(c.id), padding: false)

    Agent.update(c.store, &Map.put(&1, key, :erlang.term_to_binary(:invalid)))

    assert {:error, :invalid_execution_checkpoint} = Store.stream(c.id, c.jido)
    assert {:error, :invalid_execution_checkpoint} = Store.append(c.id, [:event], c.jido)
  end

  @tag obligation: "jido.agent_server.durable_turn.I9"
  @tag timeout: 1_000
  test "terminal cleanup unregisters immediately and deletes asynchronously", c do
    config = {Bytes, store: c.store, delete_owner: self()}
    assert :ok = Store.register(c.jido, c.id, config)
    assert {:ok, 1} = Store.append(c.id, [:graph], c.jido)
    assert {:ok, 2} = Store.append(c.id, [:more_graph], c.jido)
    assert :ok = Store.save_fact(c.id, :orphan, %{value: 1}, c.jido)

    Agent.update(c.store, fn records ->
      {batch_key, _bytes} =
        Enum.find(records, fn {key, _bytes} -> String.contains?(key, ":batches:") end)

      Map.put(records, batch_key, :erlang.term_to_binary(:damaged))
    end)

    assert :ok = Store.collect(c.jido, c.id)
    assert_receive {:checkpoint_delete_started, delete_task, key}
    assert {:error, :execution_store_unavailable} = Store.stream(c.id, c.jido)
    assert Agent.get(c.store, &map_size/1) > 3

    send(delete_task, {:continue_checkpoint_delete, key})
    eventually(fn -> Agent.get(c.store, & &1) == %{} end)
  end

  @tag obligation: ["jido.agent_server.durable_turn.I2", "jido.agent_server.durable_turn.I11"]
  test "ordinary IDs have no execution store", c do
    assert {:error, :not_found} = Store.stream("ordinary-action", c.jido)
  end

  @tag obligation: "jido.agent_server.durable_turn.I2"
  test "an unchanged workflow transition preserves the saved graph", c do
    {:ok, workflow} = Jido.Exec.compile(F.Flow)
    workflow = Runic.Workflow.enable_event_emission(workflow)
    log = Runic.Workflow.event_log(workflow)

    assert {:ok, _batch_count} = Store.append(c.id, log, c.jido)

    assert {:ok, restored} =
             Store.update_workflow(c.jido, c.id, fn current -> {:ok, current} end)

    assert Runic.Workflow.event_log(restored) == log
    assert {:ok, events} = Store.stream(c.id, c.jido)
    assert Enum.to_list(events) == log
  end

  @tag obligation: "jido.agent_server.durable_turn.I2"
  test "workflow transitions hydrate the active frontier and keep history as references", c do
    {:ok, workflow} = Jido.Exec.compile(HydrationFlow)

    executed =
      workflow
      |> Runic.Workflow.enable_event_emission()
      |> Runic.Workflow.react_until_satisfied(Jido.Exec.Frame.new(%{value: 0}))

    events =
      (Runic.Workflow.build_log(executed) ++ Enum.reverse(executed.uncommitted_events))
      |> Enum.map(fn
        %Runic.Workflow.Events.FactProduced{} = event ->
          assert :ok = Store.save_fact(c.id, event.hash, event.value, c.jido)
          %{event | value: nil}

        event ->
          event
      end)

    assert {:ok, _batch_count} = Store.append(c.id, events, c.jido)

    assert {:ok, restored} =
             Store.update_workflow(c.jido, c.id, fn current -> {:ok, current} end)

    vertices = Map.values(restored.graph.vertices)
    assert Enum.any?(vertices, &is_struct(&1, Runic.Workflow.FactRef))
    assert Enum.any?(vertices, &is_struct(&1, Runic.Workflow.Fact))
    assert Jido.Exec.result(restored) == {:ok, %{value: 2}}
  end

  @tag obligation: "jido.agent_server.durable_turn.I2"
  test "workflow transitions fully hydrate a native Batch", c do
    {:ok, workflow} = Jido.Exec.compile(BatchFlow)

    executed =
      workflow
      |> Runic.Workflow.enable_event_emission()
      |> Runic.Workflow.react_until_satisfied(Jido.Exec.Frame.new(%{items: [1, 2]}))

    events =
      (Runic.Workflow.build_log(executed) ++ Enum.reverse(executed.uncommitted_events))
      |> Enum.map(fn
        %Runic.Workflow.Events.FactProduced{} = event ->
          assert :ok = Store.save_fact(c.id, event.hash, event.value, c.jido)
          %{event | value: nil}

        event ->
          event
      end)

    assert {:ok, _batch_count} = Store.append(c.id, events, c.jido)

    assert {:ok, restored} =
             Store.update_workflow(c.jido, c.id, fn current -> {:ok, current} end)

    refute Enum.any?(restored.graph.vertices, fn {_hash, vertex} ->
             is_struct(vertex, Runic.Workflow.FactRef)
           end)

    assert Jido.Exec.result(restored) ==
             {:ok, %{items: [%{value: 2}, %{value: 3}]}}
  end

  @tag obligation: "jido.agent_server.durable_turn.I2"
  test "workflow transitions reject a missing frontier fact", c do
    {:ok, workflow} = Jido.Exec.compile(HydrationFlow)

    executed =
      workflow
      |> Runic.Workflow.enable_event_emission()
      |> Runic.Workflow.react_until_satisfied(Jido.Exec.Frame.new(%{value: 0}))

    events = Runic.Workflow.build_log(executed) ++ Enum.reverse(executed.uncommitted_events)

    detached =
      Enum.map(events, fn
        %Runic.Workflow.Events.FactProduced{} = event -> %{event | value: nil}
        event -> event
      end)

    required =
      detached
      |> Runic.Workflow.from_events(nil, fact_mode: :ref)
      |> Runic.Workflow.Rehydration.classify()
      |> Map.fetch!(:hot)

    missing =
      Enum.find(required, fn required_hash ->
        Enum.any?(events, &(event_hash(&1) == required_hash))
      end)

    assert missing

    Enum.each(events, fn
      %Runic.Workflow.Events.FactProduced{hash: ^missing} ->
        :ok

      %Runic.Workflow.Events.FactProduced{} = event ->
        assert :ok = Store.save_fact(c.id, event.hash, event.value, c.jido)

      _event ->
        :ok
    end)

    assert {:ok, _batch_count} = Store.append(c.id, detached, c.jido)

    assert {:error, :invalid_execution_checkpoint} =
             Store.update_workflow(c.jido, c.id, fn current -> {:ok, current} end)
  end

  @tag obligation: "jido.agent_server.durable_turn.I7"
  test "wait delivery rejects an execution with no saved graph", c do
    data = %{jido: c.jido, active: %{worker_id: c.id}}

    assert {:error, :missing_wait_checkpoint} =
             Jido.AgentServer.DurableTurn.deliver(data, %{
               id: "input",
               event: "event",
               payload: %{},
               wait_id: "wait"
             })
  end

  @tag obligation: "jido.agent_server.durable_turn.I2"
  test "execution identity isolates partitions, Agents, and command IDs", c do
    ids = [
      c.id,
      identity(%{c.init | partition: "south"}, "job"),
      identity(%{c.init | agent_id: "other"}, "job"),
      identity(c.init, "other")
    ]

    assert length(Enum.uniq(ids)) == 4

    for {id, index} <- Enum.with_index(ids) do
      assert :ok = Store.register(c.jido, id, c.config)
      assert {:ok, 1} = Store.append(id, [index], c.jido)
    end

    for {id, index} <- Enum.with_index(ids) do
      assert {:ok, events} = Store.stream(id, c.jido)
      assert Enum.to_list(events) == [index]
    end
  end

  @tag obligation: "jido.agent_server.durable_turn.I2"
  test "old runtime cleanup cannot remove or collect a replacement owner's checkpoint", c do
    assert {:ok, 1} = Store.append(c.id, [:replacement_graph], c.jido)
    owner = self()

    replacement =
      Task.async(fn ->
        assert :ok = Store.register(c.jido, c.id, c.config)
        send(owner, :registered)

        receive do
          :check -> Store.stream(c.id, c.jido)
        end
      end)

    assert_receive :registered
    assert {:error, :execution_owner_replaced} = Store.collect(c.jido, c.id)
    send(replacement.pid, :check)
    assert {:ok, events} = Task.await(replacement)
    assert Enum.to_list(events) == [:replacement_graph]
  end

  defp identity(init, id),
    do: {:jido_execution, Jido.namespace(init.jido), init.partition, init.agent_id, id}

  defp event_hash(%Runic.Workflow.Events.FactProduced{hash: hash}), do: hash
  defp event_hash(_event), do: nil

  defp large_session do
    %{
      id: "session-1",
      entries: [
        %{role: :user, content: String.duplicate("request ", 4_000)},
        %{role: :assistant, content: String.duplicate("response ", 4_000)}
      ]
    }
  end

  defp encoded_bytes(term), do: term |> :erlang.term_to_binary([:deterministic]) |> byte_size()

  defp use_barrier_store(c, stage) do
    config =
      {BarrierBytes, store: c.store, barrier_owner: self(), barrier_stage: stage}

    assert :ok = Store.register(c.jido, c.id, config)
  end

  defp release_fact_barrier(stage, count) do
    blocked =
      for _index <- 1..count do
        assert_receive {:fact_cas_ready, ^stage, writer, key}, 1_000
        {writer, key}
      end

    Enum.each(blocked, fn {writer, key} ->
      send(writer, {:continue_fact_cas, stage, key})
    end)
  end
end

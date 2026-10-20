defmodule JidoTest.AgentServer.DurableTurn.CheckpointStoreTest do
  use JidoTest.Case, async: true
  use Covenant.Case, component: "jido.agent_server.durable_turn", async: true

  alias Jido.AgentServer.DurableTurn.CheckpointStore, as: Store
  alias JidoTest.DurableFixtures, as: F

  defmodule Bytes do
    @behaviour Jido.Persistence.Adapter

    def get(key, opts) do
      Agent.get(opts[:store], fn records ->
        case Map.fetch(records, key) do
          {:ok, bytes} -> {:ok, bytes}
          :error -> {:error, :not_found}
        end
      end)
    end

    def compare_and_swap(key, expected, bytes, opts) do
      Agent.get_and_update(opts[:store], fn records ->
        if Map.get(records, key, :not_found) == expected,
          do: {:ok, Map.put(records, key, bytes)},
          else: {{:error, :conflict}, records}
      end)
    end
  end

  setup c do
    store = start_supervised!({Agent, fn -> %{} end})
    config = {Bytes, store: store}
    init = %{jido: c.jido, partition: "north", agent_id: "worker"}
    id = Store.identity(init, "job")
    assert :ok = Store.register(c.jido, id, config)
    %{store: store, config: config, init: init, id: id}
  end

  @tag obligation: "jido.agent_server.durable_turn.I2"
  test "initial input and graph checkpoints share one conditional byte record", c do
    assert {:error, :not_found} = Store.load(c.id, c.jido)
    assert {:error, :not_found} = Store.save(c.id, [:graph], c.jido)
    assert :ok = Store.create(c.jido, c.id)
    assert :ok = Store.create(c.jido, c.id)
    assert {:error, :not_found} = Store.load(c.id, c.jido)
    assert :ok = Store.save(c.id, [:graph], c.jido)
    assert {:ok, [:graph]} = Store.load(c.id, c.jido)

    invalid = [
      <<0>>,
      :erlang.term_to_binary(%{fmt: 99, log: []}),
      :erlang.term_to_binary(%{fmt: 1}),
      :erlang.term_to_binary(%{fmt: 1, log: %{}}),
      :erlang.term_to_binary(%{fmt: 1, log: nil, extra: true})
    ]

    for bytes <- invalid do
      Agent.update(c.store, &Map.new(&1, fn {key, _} -> {key, bytes} end))
      assert {:error, :invalid_execution_checkpoint} = Store.load(c.id, c.jido)
      assert {:error, :invalid_execution_checkpoint} = Store.create(c.jido, c.id)
      assert {:error, :invalid_execution_checkpoint} = Store.save(c.id, [:replacement], c.jido)
      assert Agent.get(c.store, &Map.values/1) == [bytes]
    end
  end

  @tag obligation: "jido.agent_server.durable_turn.I2"
  test "checkpoint keys use the stable unpadded v1 encoding", c do
    id = {:jido_execution, "n", "p", "a", "t"}
    assert :ok = Store.register(c.jido, id, c.config)
    assert :ok = Store.create(c.jido, id)

    expected =
      "jido:execution:v1:" <>
        Base.url_encode64(:erlang.term_to_binary(id), padding: false)

    assert Agent.get(c.store, &Map.keys/1) == [expected]
  end

  @tag obligation: ["jido.agent_server.durable_turn.I2", "jido.agent_server.durable_turn.I11"]
  test "ordinary IDs and invalid instance names have no execution store", c do
    assert :ok = Store.save("ordinary-action", [:ignored], c.jido)
    assert {:error, :not_found} = Store.load("ordinary-action", c.jido)

    for jido <- [nil, false, "not-an-instance"] do
      assert {:error, :execution_store_unavailable} = Store.load(c.id, jido)
      assert {:error, :execution_store_unavailable} = Store.create(jido, c.id)
    end
  end

  @tag obligation: "jido.agent_server.durable_turn.I2"
  test "an unchanged workflow transition preserves the saved graph", c do
    {:ok, workflow} = Jido.Exec.compile(F.Flow)
    workflow = Runic.Workflow.enable_event_emission(workflow)
    log = Runic.Workflow.event_log(workflow)

    assert :ok = Store.create(c.jido, c.id)
    assert :ok = Store.save(c.id, log, c.jido)

    assert {:ok, restored} =
             Store.update_workflow(c.jido, c.id, fn current -> {:ok, current} end)

    assert Runic.Workflow.event_log(restored) == log
    assert {:ok, ^log} = Store.load(c.id, c.jido)
  end

  @tag obligation: "jido.agent_server.durable_turn.I7"
  test "wait delivery rejects an execution marker with no saved graph", c do
    assert :ok = Store.create(c.jido, c.id)

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
      Store.identity(%{c.init | partition: "south"}, "job"),
      Store.identity(%{c.init | agent_id: "other"}, "job"),
      Store.identity(c.init, "other")
    ]

    assert length(Enum.uniq(ids)) == 4

    for {id, index} <- Enum.with_index(ids) do
      assert :ok = Store.register(c.jido, id, c.config)
      assert :ok = Store.create(c.jido, id)
      assert :ok = Store.save(id, [index], c.jido)
    end

    for {id, index} <- Enum.with_index(ids), do: assert(Store.load(id, c.jido) == {:ok, [index]})
  end

  @tag obligation: "jido.agent_server.durable_turn.I2"
  test "old runtime cleanup cannot remove the replacement owner's registration", c do
    owner = self()

    replacement =
      Task.async(fn ->
        assert :ok = Store.register(c.jido, c.id, c.config)
        send(owner, :registered)
        receive do: (:close -> Store.unregister(c.jido, c.id))
      end)

    assert_receive :registered
    assert :ok = Store.unregister(c.jido, c.id)
    assert :ok = Store.create(c.jido, c.id)
    send(replacement.pid, :close)
    assert :ok = Task.await(replacement)
    assert {:error, :execution_store_unavailable} = Store.load(c.id, c.jido)
  end
end

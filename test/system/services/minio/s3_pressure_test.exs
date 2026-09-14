Code.require_file("../../support/case.exs", __DIR__)

defmodule JidoTest.System.Services.S3Pressure do
  use JidoTest.System.Case, async: false
  @moduletag :service
  @moduletag adapter: :s3_minio

  alias Jido.AgentServer, as: Server
  alias Jido.Persistence
  alias JidoTest.RecoverableDeliveryAgent, as: Probe
  alias JidoTest.RecoverableDeliverySink, as: Sink
  alias JidoTest.System.Observability

  test "many real S3 writers have one winner at each revision", c do
    server = start_agent(c)
    id = Server.agent(server).id
    signal = Probe.record_and_deliver_signal!("seed", 7)
    assert {:ok, _agent} = Server.call(server, signal)
    completed(c, server, %{"seed" => 7})
    stop_agent(c, server)

    {adapter, adapter_opts} = c.store
    probe_key = "s3-pressure-create-#{id}"

    creates =
      race(48, fn value ->
        bytes = <<value>>
        {adapter.compare_and_swap(probe_key, :not_found, bytes, adapter_opts), bytes}
      end)

    assert [{:ok, created_bytes}] = Enum.filter(creates, &match?({:ok, _}, &1))
    assert Enum.count(creates, &match?({{:error, :conflict}, _}, &1)) == 47
    assert {:ok, ^created_bytes, _token} = adapter.get(probe_key, adapter_opts)

    for round <- 1..8 do
      assert {:ok, _bytes, token} = adapter.get(probe_key, adapter_opts)

      updates =
        race(24, fn value ->
          bytes = "round-#{round}-#{value}"
          {adapter.compare_and_swap(probe_key, {:token, token}, bytes, adapter_opts), bytes}
        end)

      assert [{:ok, updated_bytes}] = Enum.filter(updates, &match?({:ok, _}, &1))
      assert Enum.count(updates, &match?({{:error, :conflict}, _}, &1)) == 23
      assert {:ok, ^updated_bytes, _token} = adapter.get(probe_key, adapter_opts)
    end

    assert :ok = adapter.delete(probe_key, adapter_opts)

    for round <- 1..8 do
      assert {:ok, current, revision} = load(c, id)

      writes =
        race(24, fn value ->
          candidate = %{current | state: %{current.state | value: round * 1_000 + value}}

          {Persistence.save_agent(c.store, candidate,
             instance: c.jido,
             namespace: c.namespace,
             expected_revision: revision,
             revision: revision + 1
           ), candidate}
        end)

      assert [{:ok, winner}] = Enum.filter(writes, &match?({:ok, _}, &1))
      assert Enum.count(writes, &match?({{:error, :conflict}, _}, &1)) == 23
      assert {:ok, ^winner, next_revision} = load(c, id)
      assert next_revision == revision + 1
    end

    assert {:ok, final, final_revision} = load(c, id)
    restored = start_agent(c, id: id, restore: :required)
    assert Server.snapshot(restored) == %{agent: final, state_version: final_revision}
    stop_agent(c, restored)
    assert_empty_agent_pool(c)

    assert Sink.records(c.jido) == %{"seed" => 7}
    assert Enum.map(Sink.attempts(c.jido), & &1.effect_id) == ["seed"]
    Observability.assert_turn(c.observer, signal, :ok, true)
    Observability.assert_persistence(c.observer, :conflict)
  end

  test "an accepted MinIO write with a lost reply is not retried", c do
    server = start_agent(c)
    id = Server.agent(server).id
    signal = Probe.record_and_deliver_signal!("lost-seed", 7)
    assert {:ok, _agent} = Server.call(server, signal)
    completed(c, server, %{"lost-seed" => 7})
    stop_agent(c, server)
    assert {:ok, initial, revision} = load(c, id)

    {adapter, adapter_opts} = c.store
    request = Keyword.fetch!(adapter_opts, :request_fn)
    {:ok, calls} = Elixir.Agent.start_link(fn -> 0 end)
    on_exit(fn -> if Process.alive?(calls), do: Elixir.Agent.stop(calls) end)

    lost_reply = fn operation ->
      case operation.method do
        :put ->
          Elixir.Agent.update(calls, &(&1 + 1))
          assert {:ok, %{status: 200}} = request.(operation)
          {:error, {:indeterminate, :lost_reply}}

        _ ->
          request.(operation)
      end
    end

    opts = Keyword.put(adapter_opts, :request_fn, lost_reply)
    candidate = %{initial | state: %{initial.state | value: 91}}

    assert {:error, {:indeterminate, :lost_reply}} =
             Persistence.save_agent({adapter, opts}, candidate,
               instance: c.jido,
               namespace: c.namespace,
               expected_revision: revision,
               revision: revision + 1
             )

    assert Elixir.Agent.get(calls, & &1) == 1
    assert {:ok, ^candidate, next_revision} = load(c, id)
    assert next_revision == revision + 1

    assert {:error, :conflict} =
             Persistence.save_agent(c.store, candidate,
               instance: c.jido,
               namespace: c.namespace,
               expected_revision: revision,
               revision: revision + 1
             )

    restored = start_agent(c, id: id, restore: :required)
    assert Server.snapshot(restored) == %{agent: candidate, state_version: next_revision}
    stop_agent(c, restored)
    assert_empty_agent_pool(c)
    assert Sink.records(c.jido) == %{"lost-seed" => 7}
    assert Enum.map(Sink.attempts(c.jido), & &1.effect_id) == ["lost-seed"]
    Observability.assert_turn(c.observer, signal, :ok, true)
    Observability.assert_persistence(c.observer, :indeterminate)
    Observability.assert_persistence(c.observer, :conflict)
  end

  defp race(count, fun) do
    owner = self()

    tasks =
      for value <- 1..count do
        Task.async(fn ->
          send(owner, {:ready, self()})

          receive do
            :go -> fun.(value)
          end
        end)
      end

    for %{pid: pid} <- tasks, do: assert_receive({:ready, ^pid}, 10_000)
    for %{pid: pid} <- tasks, do: send(pid, :go)
    Enum.map(tasks, &Task.await(&1, 30_000))
  end
end

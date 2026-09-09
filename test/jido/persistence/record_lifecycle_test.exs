defmodule JidoTest.Persistence.RecordLifecycleTest do
  use JidoTest.Case, async: false

  alias Jido.Agent
  alias Jido.Persistence
  alias Jido.Persistence.ETS
  alias JidoTest.AgentRuntimeFixtures.RuntimeAgent

  defmodule BarrierAdapter do
    @behaviour Jido.Persistence.Adapter

    @impl true
    def get(key, opts) do
      result = ETS.get(key, opts)
      send(Keyword.fetch!(opts, :observer), {:persistence_read, self(), result})

      receive do
        :continue -> result
      after
        5_000 -> {:error, {:rejected, :barrier_timeout}}
      end
    end

    @impl true
    defdelegate compare_and_swap(key, expected, value, opts), to: ETS
  end

  defp persistence(name) do
    {ETS, table: :"record_lifecycle_#{name}_#{System.unique_integer([:positive])}"}
  end

  test "a new persistent activation stores revision zero before start returns", %{jido: jido} do
    persistence = persistence(:initial)
    id = unique_id("initial-record")

    assert {:ok, pid} =
             Jido.start_agent(jido, RuntimeAgent,
               id: id,
               persistence: persistence,
               restore: false
             )

    assert Process.alive?(pid)

    assert {:ok, initial, 0} =
             Persistence.load_agent_with_revision(persistence, RuntimeAgent, id, instance: jido)

    assert initial == RuntimeAgent.new!(id: id)

    {ETS, opts} = persistence
    key = Persistence.agent_key(jido, RuntimeAgent, id)
    assert {:ok, bytes} = ETS.get(key, opts)
    record = :erlang.binary_to_term(bytes, [:safe])

    assert record == %{
             format: 2,
             kind: :active,
             instance: jido,
             agent_module: RuntimeAgent,
             agent_vsn: RuntimeAgent.vsn(),
             agent_id: id,
             partition: nil,
             revision: 0,
             checkpoint: record.checkpoint
           }
  end

  test "restore modes create only where the contract permits", %{jido: jido} do
    required_store = persistence(:required_missing)
    required_id = unique_id("required-missing")

    assert {:error, :not_found} =
             Jido.start_agent(jido, RuntimeAgent,
               id: required_id,
               persistence: required_store,
               restore: :required
             )

    assert {:error, :not_found} =
             Persistence.load_agent(required_store, RuntimeAgent, required_id, instance: jido)

    if_found_store = persistence(:if_found_missing)
    if_found_id = unique_id("if-found-missing")

    assert {:ok, _pid} =
             Jido.start_agent(jido, RuntimeAgent,
               id: if_found_id,
               persistence: if_found_store,
               restore: :if_found
             )

    assert {:ok, _agent, 0} =
             Persistence.load_agent_with_revision(if_found_store, RuntimeAgent, if_found_id,
               instance: jido
             )

    active_store = persistence(:active_conflict)
    active_id = unique_id("active-conflict")
    active = RuntimeAgent.new!(id: active_id)
    assert :ok = Persistence.save_agent(active_store, active, instance: jido)

    assert {:error, {:persistence_failed, :conflict}} =
             Jido.start_agent(jido, RuntimeAgent,
               id: active_id,
               persistence: active_store,
               restore: false
             )

    tombstone_store = persistence(:tombstone_conflict)
    tombstone_id = unique_id("tombstone-conflict")

    assert :ok =
             Persistence.delete_agent(tombstone_store, RuntimeAgent, tombstone_id, instance: jido)

    assert {:error, {:persistence_failed, :conflict}} =
             Jido.start_agent(jido, RuntimeAgent,
               id: tombstone_id,
               persistence: tombstone_store,
               restore: false
             )
  end

  test "logical deletion writes compact tombstones and fences delayed writers", %{jido: jido} do
    persistence = persistence(:tombstone)
    active = RuntimeAgent.new!(id: unique_id("deleted"), state: %{events: [:saved], ticks: 2})

    assert :ok = Persistence.save_agent(persistence, active, instance: jido, revision: 3)
    assert :ok = Persistence.delete_agent(persistence, RuntimeAgent, active.id, instance: jido)

    assert {:error, :deleted} =
             Persistence.load_agent(persistence, RuntimeAgent, active.id, instance: jido)

    {ETS, opts} = persistence
    key = Persistence.agent_key(jido, RuntimeAgent, active.id)
    assert {:ok, bytes} = ETS.get(key, opts)

    assert :erlang.binary_to_term(bytes, [:safe]) == %{
             format: 2,
             kind: :tombstone,
             instance: jido,
             agent_module: RuntimeAgent,
             agent_id: active.id,
             partition: nil,
             revision: 3
           }

    assert {:error, :conflict} =
             Persistence.save_agent(persistence, active,
               instance: jido,
               revision: 4,
               expected_revision: 3
             )

    missing_id = unique_id("missing-delete")
    assert :ok = Persistence.delete_agent(persistence, RuntimeAgent, missing_id, instance: jido)
    missing_key = Persistence.agent_key(jido, RuntimeAgent, missing_id)
    assert {:ok, missing_bytes} = ETS.get(missing_key, opts)

    assert %{format: 2, kind: :tombstone, revision: 0} =
             :erlang.binary_to_term(missing_bytes, [:safe])
  end

  test "a delete race preserves a newer active revision", %{jido: jido} do
    {ETS, opts} = persistence = persistence(:delete_race)
    agent = RuntimeAgent.new!(id: unique_id("delete-race"), state: %{events: [:old]})
    winner = %{agent | state: %{agent.state | events: [:winner]}}

    assert :ok = Persistence.save_agent(persistence, agent, instance: jido, revision: 1)
    barrier = {BarrierAdapter, Keyword.put(opts, :observer, self())}

    task =
      Task.async(fn ->
        Persistence.delete_agent(barrier, RuntimeAgent, agent.id, instance: jido)
      end)

    assert_receive {:persistence_read, reader, {:ok, _bytes}}, 1_000

    assert :ok =
             Persistence.save_agent(persistence, winner,
               instance: jido,
               revision: 2,
               expected_revision: 1
             )

    send(reader, :continue)
    assert {:error, :conflict} = Task.await(task)

    assert {:ok, ^winner, 2} =
             Persistence.load_agent_with_revision(persistence, RuntimeAgent, agent.id,
               instance: jido
             )
  end

  test "legacy format one remains readable" do
    {ETS, opts} = persistence = persistence(:legacy)
    agent = RuntimeAgent.new!(id: unique_id("legacy"), state: %{events: [:legacy]})
    assert {:ok, checkpoint} = Agent.checkpoint(agent)

    record = %{
      format: 1,
      kind: :agent,
      instance: nil,
      agent_module: RuntimeAgent,
      agent_id: agent.id,
      partition: nil,
      revision: 7,
      checkpoint: checkpoint
    }

    key = Persistence.agent_key(nil, RuntimeAgent, agent.id)
    assert :ok = ETS.put(key, :erlang.term_to_binary(record), opts)

    assert {:ok, ^agent, 7} =
             Persistence.load_agent_with_revision(persistence, RuntimeAgent, agent.id)
  end

  test "outer definition and record changes fail closed without a replacement write" do
    {ETS, opts} = persistence = persistence(:fail_closed)
    agent = RuntimeAgent.new!(id: unique_id("fail-closed"))
    key = Persistence.agent_key(nil, RuntimeAgent, agent.id)
    assert :ok = Persistence.save_agent(persistence, agent)
    assert {:ok, original} = ETS.get(key, opts)
    record = :erlang.binary_to_term(original, [:safe])

    different_definition = %{record | agent_vsn: RuntimeAgent.vsn() + 1}
    assert :ok = ETS.put(key, :erlang.term_to_binary(different_definition), opts)

    assert {:error, %Jido.Error.ValidationError{details: %{code: :definition_mismatch}}} =
             Persistence.load_agent(persistence, RuntimeAgent, agent.id)

    for changed <- [
          %{record | format: 99},
          %{record | kind: :future},
          Map.put(record, :future_field, true)
        ] do
      bytes = :erlang.term_to_binary(changed)
      assert :ok = ETS.put(key, bytes, opts)
      assert {:error, _reason} = Persistence.load_agent(persistence, RuntimeAgent, agent.id)
      assert {:error, _reason} = Persistence.save_agent(persistence, agent, revision: 1)
      assert {:ok, ^bytes} = ETS.get(key, opts)
    end
  end
end

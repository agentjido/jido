defmodule JidoTest.Persistence.RecordLifecycleTest do
  use JidoTest.Case, async: false
  use Covenant.Case, component: "jido.persistence", async: false

  alias Jido.Persistence
  alias Jido.Persistence.{ETS, Record}
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

  @tag obligation: "jido.persistence.I13"
  test "logical deletion writes compact tombstones and fences delayed writers", %{jido: jido} do
    persistence = persistence(:tombstone)

    active =
      RuntimeAgent.instantiate!(id: unique_id("deleted"), state: %{events: [:saved], ticks: 2})

    assert :ok = Persistence.save_agent(persistence, active, instance: jido, revision: 3)
    assert :ok = Persistence.delete_agent(persistence, RuntimeAgent, active.id, instance: jido)

    assert {:error, :deleted} =
             Persistence.load_agent(persistence, RuntimeAgent, active.id, instance: jido)

    {ETS, opts} = persistence

    key =
      Persistence.agent_key(Jido.Agent.Ref.new!(namespace: Jido.namespace(jido), id: active.id))

    assert {:ok, bytes} = ETS.get(key, opts)

    assert :erlang.binary_to_term(bytes, [:safe]) == %{
             fmt: 4,
             kind: :tombstone,
             namespace: Jido.namespace(jido),
             agent_module: RuntimeAgent,
             agent_id: active.id,
             partition: nil,
             rev: 3
           }

    assert {:error, :conflict} =
             Persistence.save_agent(persistence, active,
               instance: jido,
               revision: 4,
               expected_revision: 3
             )

    missing_id = unique_id("missing-delete")
    assert :ok = Persistence.delete_agent(persistence, RuntimeAgent, missing_id, instance: jido)

    missing_key =
      Persistence.agent_key(Jido.Agent.Ref.new!(namespace: Jido.namespace(jido), id: missing_id))

    assert {:ok, missing_bytes} = ETS.get(missing_key, opts)

    assert %{fmt: 4, kind: :tombstone, rev: 0} =
             :erlang.binary_to_term(missing_bytes, [:safe])
  end

  @tag obligation: "jido.persistence.I13"
  test "a delete race preserves a newer active revision", %{jido: jido} do
    {ETS, opts} = persistence = persistence(:delete_race)
    agent = RuntimeAgent.instantiate!(id: unique_id("delete-race"), state: %{events: [:old]})
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

  @tag obligation: "jido.persistence.I5"
  test "old record formats fail without changing stored bytes" do
    {ETS, opts} = persistence = persistence(:old_formats)
    agent = RuntimeAgent.instantiate!(id: unique_id("old-formats"))
    assert {:ok, checkpoint} = Jido.Persistence.snapshot(agent)
    key = Persistence.agent_key(Jido.Agent.Ref.new!(namespace: "persistence-test", id: agent.id))

    for format <- [1, 2] do
      record = %{
        format: format,
        kind: if(format == 1, do: :agent, else: :active),
        instance: nil,
        agent_module: RuntimeAgent,
        agent_id: agent.id,
        partition: nil,
        revision: 7,
        checkpoint: checkpoint
      }

      bytes = :erlang.term_to_binary(record)
      assert :ok = ETS.put(key, bytes, opts)

      assert {:error, {:invalid_persistence_record, :format}} =
               Persistence.load_agent(persistence, RuntimeAgent, agent.id,
                 namespace: "persistence-test"
               )

      assert {:error, {:invalid_persistence_record, :format}} =
               Persistence.save_agent(persistence, agent,
                 namespace: "persistence-test",
                 revision: 8
               )

      assert {:error, {:invalid_persistence_record, :format}} =
               Persistence.delete_agent(persistence, RuntimeAgent, agent.id,
                 namespace: "persistence-test"
               )

      assert {:ok, ^bytes} = ETS.get(key, opts)
    end
  end

  @tag obligation: "jido.persistence.I5"
  test "format three records remain readable during adapter cutover" do
    {ETS, opts} = persistence = persistence(:format_three)
    agent = RuntimeAgent.instantiate!(id: unique_id("format-three"))
    namespace = "persistence-test"
    ref = Jido.Agent.Ref.new!(namespace: namespace, id: agent.id)
    key = Persistence.agent_key(ref)
    assert {:ok, checkpoint} = Persistence.snapshot(agent)

    active = %{
      format: 3,
      kind: :active,
      namespace: namespace,
      agent_module: RuntimeAgent,
      agent_id: agent.id,
      partition: nil,
      revision: 3,
      agent_vsn: agent.vsn,
      checkpoint: checkpoint
    }

    active_bytes = :erlang.term_to_binary(active)
    assert :ok = ETS.put(key, active_bytes, opts)

    assert {:ok, ^agent, 3} =
             Persistence.load_agent_with_revision(persistence, RuntimeAgent, agent.id,
               namespace: namespace
             )

    assert {:ok, ^active_bytes} = ETS.get(key, opts)
    assert Record.kind(active) == :active
    assert Record.format(active) == 3
    assert Record.revision(active) == 3
    assert Record.agent_vsn(active) == agent.vsn

    tombstone = Map.drop(active, [:agent_vsn, :checkpoint]) |> Map.put(:kind, :tombstone)
    tombstone_bytes = :erlang.term_to_binary(tombstone)
    assert :ok = ETS.put(key, tombstone_bytes, opts)

    assert {:error, :deleted} =
             Persistence.load_agent(persistence, RuntimeAgent, agent.id, namespace: namespace)

    assert :ok =
             Persistence.delete_agent(persistence, RuntimeAgent, agent.id, namespace: namespace)

    assert {:ok, ^tombstone_bytes} = ETS.get(key, opts)
    assert Record.kind(tombstone) == :tombstone
  end

  @tag obligation: ["jido.persistence.I5", "jido.persistence.I12"]
  test "outer definition and record changes fail closed without a replacement write" do
    {ETS, opts} = persistence = persistence(:fail_closed)
    agent = RuntimeAgent.instantiate!(id: unique_id("fail-closed"))
    key = Persistence.agent_key(Jido.Agent.Ref.new!(namespace: "persistence-test", id: agent.id))
    assert :ok = Persistence.save_agent(persistence, agent, namespace: "persistence-test")
    assert {:ok, original} = ETS.get(key, opts)
    record = :erlang.binary_to_term(original, [:safe])

    different_definition = %{record | vsn: RuntimeAgent.vsn() + 1}
    assert :ok = ETS.put(key, :erlang.term_to_binary(different_definition), opts)

    assert {:error, {:invalid_persistence_record, :vsn}} =
             Persistence.load_agent(persistence, RuntimeAgent, agent.id,
               namespace: "persistence-test"
             )

    for changed <- [
          %{record | fmt: 99},
          %{record | kind: :future},
          Map.put(record, :future_field, true)
        ] do
      bytes = :erlang.term_to_binary(changed)
      assert :ok = ETS.put(key, bytes, opts)

      assert {:error, _reason} =
               Persistence.load_agent(persistence, RuntimeAgent, agent.id,
                 namespace: "persistence-test"
               )

      assert {:error, _reason} =
               Persistence.save_agent(persistence, agent,
                 namespace: "persistence-test",
                 revision: 1
               )

      assert {:ok, ^bytes} = ETS.get(key, opts)
    end
  end
end

defmodule Jido.Agent.SerializationContractTest do
  use JidoTest.Case, async: true

  alias Jido.Agent.Codec
  alias Jido.Authoring.Registry
  alias Jido.Persistence
  alias JidoTest.Persistence.CheckpointIdentityProbe, as: Probe
  alias JidoTest.Persistence.ProbeStore, as: Store

  test "Agent persistence uses a separate namespace and rejects an old envelope" do
    opts = [store: start_supervised!(Store)]
    store = {Store, opts}
    agent = Probe.instantiate!(id: unique_id())
    assert :ok = Persistence.save_agent(store, agent, namespace: "persistence-test")
    key = Persistence.agent_key(Jido.Agent.Ref.new!(namespace: "persistence-test", id: agent.id))
    assert "jido:agent:v1:" <> _identity = key
    assert {:ok, bytes} = Store.get(key, opts)
    record = :erlang.binary_to_term(bytes, [:safe])
    assert record.fmt == 4
    assert record.kind == :active
    assert record.vsn == Probe.vsn()
    assert record.agent_id == agent.id

    # These old identifiers are intentional rejection fixtures.
    old_record =
      record
      |> Map.drop([:agent_module, :agent_id])
      |> Map.merge(%{kind: :actor, actor_module: Probe, actor_id: agent.id})

    old_bytes = :erlang.term_to_binary(old_record)
    old_key = String.replace_prefix(key, "jido:agent:v1:", "jido:actor:v1:")
    assert :ok = Store.delete(key, opts)
    assert :ok = Store.put(old_key, old_bytes, opts)

    assert {:error, :not_found} =
             Persistence.load_agent(store, Probe, agent.id, namespace: "persistence-test")

    assert :ok = Store.put(key, old_bytes, opts)

    assert {:error, {:invalid_persistence_record, :kind}} =
             Persistence.load_agent(store, Probe, agent.id, namespace: "persistence-test")
  end

  test "authoring JSON preserves the Agent definition through a trusted Registry" do
    definition = Probe.definition()

    registry =
      Registry.new!(%{
        "agents/probe/v1" => {:agent, Probe},
        "schemas/probe/v1" => {:schema, definition.schema}
      })

    assert {:ok, document} = Codec.encode(definition, registry)
    assert {:ok, ^definition} = Codec.decode(document, registry)
    assert {:error, _} = Codec.decode(document, %{})
    assert {:error, _} = Codec.decode(%{}, registry)
  end
end

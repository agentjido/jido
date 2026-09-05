defmodule JidoTest.Agent.NamingContractTest do
  use JidoTest.Case, async: true

  alias Jido.Agent.Codec
  alias Jido.Examples.CheckpointIdentityProbe, as: Probe
  alias Jido.Examples.PersistenceProbeStore, as: Store
  alias Jido.Persistence

  test "Agent persistence uses a separate namespace and rejects an old envelope" do
    opts = [store: start_supervised!(Store)]
    store = {Store, opts}
    agent = Probe.new!(id: unique_id())
    assert :ok = Persistence.save_agent(store, agent)
    key = Persistence.agent_key(nil, Probe, agent.id)
    assert "jido:agent:v1:" <> _identity = key
    assert {:ok, bytes} = Store.get(key, opts)
    record = :erlang.binary_to_term(bytes, [:safe])
    assert record.kind == :agent
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
    assert {:error, :not_found} = Persistence.load_agent(store, Probe, agent.id)
    assert :ok = Store.put(key, old_bytes, opts)

    assert {:error, {:invalid_persistence_record, :kind}} =
             Persistence.load_agent(store, Probe, agent.id)
  end

  test "Agent authoring JSON declares its type and rejects the old type" do
    assert {:ok, document, registry} = Codec.encode(Probe.agent())
    assert document["type"] == "jido.agent"
    assert {:ok, _definition} = Codec.decode(document, registry)
    assert {:error, _reason} = Codec.decode(%{document | "type" => "jido.actor"}, registry)
  end
end

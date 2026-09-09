defmodule JidoPublicConsumerTest do
  use ExUnit.Case, async: false

  alias Jido.Agent.Ref
  alias Jido.Persistence
  alias Jido.Persistence.ETS
  alias JidoPublicConsumer.{Agent, Plugin, Topology}

  test "the packaged public API supports the four Plugin owners and core runtime seams" do
    assert {:ok, manifest} = Jido.Plugin.manifest(Plugin)
    assert manifest.agent == JidoPublicConsumer.AgentFacet
    assert manifest.agent_server == JidoPublicConsumer.ServerFacet
    assert manifest.persistence == JidoPublicConsumer.PersistenceFacet
    assert manifest.topology == JidoPublicConsumer.TopologyFacet

    signal = Jido.Signal.new!("consumer.ping", %{}, source: "/public-consumer")
    assert signal.type == "consumer.ping"

    agent = Agent.new!(id: "persisted")
    assert agent.state.plugin_count == 0

    table = :jido_public_consumer_persistence
    storage = {ETS, table: table}
    opts = [namespace: "release/public-consumer", partition: "local"]
    assert :ok = Persistence.create_agent(storage, agent, opts)

    assert {:ok, restored, 0} =
             Persistence.load_agent_with_revision(storage, Agent, agent.id, opts)

    assert restored == agent

    ref =
      Ref.new!(
        namespace: "release/public-consumer",
        partition: "local",
        id: "live"
      )

    start_supervised!(
      {Jido, name: JidoPublicConsumer.Runtime, namespace: ref.namespace, persistence: storage},
      id: JidoPublicConsumer.Runtime
    )

    assert {:ok, server} = Jido.start_agent_ref(JidoPublicConsumer.Runtime, ref, Agent)
    assert Jido.resolve_agent(JidoPublicConsumer.Runtime, ref) == {:ok, server}
    assert :ok = Jido.stop_agent_ref(JidoPublicConsumer.Runtime, ref)

    topology = Topology.new!(id: "public-consumer")
    assert Map.has_key?(topology.plan.resources, "bus/inbox")
  end
end

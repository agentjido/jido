defmodule JidoTest.Examples.Applications.IdentityTest do
  use JidoTest.Case, async: false

  @moduletag :example

  alias Jido.AgentServer, as: Server
  alias Jido.Signal
  alias Jido.Tracing.Trace
  alias Jido.Examples.Applications.Crypto
  alias Jido.Examples.Applications.Identity.Agent

  test "a private key proves identity and the Agent signs its correlated reply", %{jido: jido} do
    {peer_public, peer_private} = Crypto.peer_key_pair()
    {agent_public, _agent_private} = Crypto.agent_key_pair()

    {:ok, agent_server} =
      Jido.start_agent(jido, Agent,
        id: unique_id("identity"),
        default_dispatch: {:pid, target: self()}
      )

    unsigned =
      Signal.new!(
        "identity.challenge",
        %{"challenge" => "prove-control"},
        source: "/identity/peer"
      )

    assert {:ok, signed} = Crypto.sign(unsigned, peer_private, peer_public, "identity-once")
    assert {:ok, committed} = Server.call(agent_server, signed)
    assert committed.state.accepted == 1
    assert committed.state.last_public_key == Base.encode16(peer_public, case: :lower)

    assert_receive {:signal, %Signal{type: "identity.accepted"} = reply}
    assert {:ok, _nonce} = Crypto.verify(reply, agent_public)
    assert Trace.get(reply).causation_id == signed.id

    assert {:error, :replayed_signal} = Server.call(agent_server, signed)
    assert Server.agent(agent_server).state.accepted == 1

    assert {:ok, forged} =
             unsigned
             |> Map.put(:id, Jido.Signal.ID.generate!())
             |> Crypto.sign(peer_private, peer_public, "identity-forged")

    forged = %{forged | data: %{"challenge" => "changed-after-signing"}}
    assert {:error, :invalid_signature} = Server.call(agent_server, forged)
    assert Server.agent(agent_server).state.accepted == 1
  end
end

defmodule JidoTest.Examples.Applications.SecureSignalTest do
  use JidoTest.Case, async: false

  @moduletag :example

  alias Jido.AgentServer, as: Server
  alias Jido.Signal
  alias Jido.Tracing.Trace
  alias Jido.Examples.Applications.Crypto
  alias Jido.Examples.Applications.SecureSignal.Agent

  test "identity verifies ciphertext before secure admission decrypts it", %{jido: jido} do
    {peer_public, peer_private} = Crypto.peer_key_pair()
    {agent_public, _agent_private} = Crypto.agent_key_pair()
    key = Crypto.secure_key()

    {:ok, agent_server} =
      Jido.start_agent(jido, Agent,
        id: unique_id("secure-signal"),
        default_dispatch: {:pid, target: self()}
      )

    unsigned =
      Signal.new!(
        "secure.request",
        %{"message_id" => "message-1"},
        source: "/secure/peer"
      )

    envelope = Crypto.encrypt(unsigned, key, %{"secret" => "swordfish"})
    encrypted = %{unsigned | data: Map.put(unsigned.data, "secure", envelope)}
    assert {:ok, signed} = Crypto.sign(encrypted, peer_private, peer_public, "secure-once")

    assert {:ok, committed} = Server.call(agent_server, signed)
    assert committed.state.accepted == 1
    assert committed.state.peer == Base.encode16(peer_public, case: :lower)
    refute Map.has_key?(committed.state, :secure)

    assert_receive {:signal, %Signal{type: "secure.accepted"} = reply}
    assert {:ok, _nonce} = Crypto.verify(reply, agent_public)
    assert Trace.get(reply).causation_id == signed.id

    reply_envelope = reply.data["secure"]
    refute reply_envelope == %{"receipt" => "swordfish:accepted"}

    assert {:ok, %{"receipt" => "swordfish:accepted"}} =
             Crypto.decrypt(reply, key, reply_envelope)
  end
end

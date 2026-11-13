Code.require_file("../support/crypto.ex", __DIR__)
Code.require_file("identity_plugin.ex", __DIR__)
Code.require_file("secure_signal_plugin.ex", __DIR__)
Code.require_file("secure_signal.ex", __DIR__)

defmodule Jido.Examples.Plugins.SecureSignalTest do
  use Jido.Test.Case, async: false
  @moduletag :integration

  alias Jido.AgentServer, as: Server
  alias Jido.Signal
  alias Jido.Signal.Context, as: SignalContext
  alias Jido.Examples.Plugins.Crypto
  alias Jido.Examples.Plugins.SecureSignal.Agent

  test "identity verifies ciphertext before secure admission decrypts it", %{jido: jido} do
    {peer_public, peer_private} = Crypto.peer_key_pair()
    {agent_public, _agent_private} = Crypto.agent_key_pair()
    key = Crypto.secure_key()

    {:ok, agent_server} =
      Jido.Test.AgentServer.ExampleRuntime.start_agent(jido, Agent, id: unique_id("secure-signal"))

    unsigned =
      Signal.new!(
        "examples.plugins.secure_signal.request",
        %{"message_id" => "message-1"},
        source: "/secure/peer"
      )

    envelope = Crypto.encrypt(unsigned, key, %{"secret" => "swordfish"})
    encrypted = %{unsigned | data: Map.put(unsigned.data, "secure", envelope)}
    assert {:ok, signed} = Crypto.sign(encrypted, peer_private, peer_public, "secure-once")

    assert {:ok, %Jido.AgentServer.TurnResult{status: :committed, reply: %Signal{} = reply}} =
             Server.call(agent_server, signed)

    committed = Server.snapshot(agent_server).agent
    assert committed.state.accepted == 1
    assert committed.state.peer == Base.encode16(peer_public, case: :lower)
    refute Map.has_key?(committed.state, :secure)

    assert reply.type == "examples.plugins.secure_signal.accepted"

    assert {:ok, _nonce} = Crypto.verify(reply, agent_public)
    assert SignalContext.get_trace(reply).causation_id == signed.id

    reply_envelope = reply.data["secure"]
    refute reply_envelope == %{"receipt" => "swordfish:accepted"}

    assert {:ok, %{"receipt" => "swordfish:accepted"}} =
             Crypto.decrypt(reply, key, reply_envelope)
  end
end

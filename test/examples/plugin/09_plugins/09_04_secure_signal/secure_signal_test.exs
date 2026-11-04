Code.require_file("../../../support/loader.exs", __DIR__)

alias JidoTest.Examples.Loader
Loader.require_source!("plugin/09_plugins/support/crypto.ex")
Loader.require_source!("plugin/09_plugins/09_04_secure_signal/identity_plugin.ex")
Loader.require_source!("plugin/09_plugins/09_04_secure_signal/secure_signal_plugin.ex")
Loader.require_source!("plugin/09_plugins/09_04_secure_signal/secure_signal.ex")

defmodule JidoTest.Examples.Plugins.SecureSignalTest do
  use JidoTest.Case, async: false
  @moduletag :example

  setup_all do
    JidoTest.Examples.Loader.require_source!("plugin/09_plugins/09_04_secure_signal/secure_signal.ex")
    :ok
  end

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
      JidoTest.ExampleRuntime.start_agent(jido, Agent, id: unique_id("secure-signal"))

    unsigned =
      Signal.new!(
        "examples.plugins.secure_signal.request",
        %{"message_id" => "message-1"},
        source: "/secure/peer"
      )

    envelope = Crypto.encrypt(unsigned, key, %{"secret" => "swordfish"})
    encrypted = %{unsigned | data: Map.put(unsigned.data, "secure", envelope)}
    assert {:ok, signed} = Crypto.sign(encrypted, peer_private, peer_public, "secure-once")

    assert {:ok, committed, _directives} = Server.call(agent_server, signed)
    assert committed.state.accepted == 1
    assert committed.state.peer == Base.encode16(peer_public, case: :lower)
    refute Map.has_key?(committed.state, :secure)

    assert_receive %Signal{type: "examples.plugins.secure_signal.accepted"} = reply

    assert {:ok, _nonce} = Crypto.verify(reply, agent_public)
    assert SignalContext.get_trace(reply).causation_id == signed.id

    reply_envelope = reply.data["secure"]
    refute reply_envelope == %{"receipt" => "swordfish:accepted"}

    assert {:ok, %{"receipt" => "swordfish:accepted"}} =
             Crypto.decrypt(reply, key, reply_envelope)
  end
end

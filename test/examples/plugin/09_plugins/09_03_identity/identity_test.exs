Code.require_file("../../../support/loader.exs", __DIR__)

alias JidoTest.Examples.Loader
Loader.require_source!("plugin/09_plugins/support/crypto.ex")
Loader.require_source!("plugin/09_plugins/09_03_identity/identity_plugin.ex")
Loader.require_source!("plugin/09_plugins/09_03_identity/identity.ex")

defmodule JidoTest.Examples.Plugins.IdentityTest do
  use JidoTest.Case, async: false
  @moduletag :example

  setup_all do
    JidoTest.Examples.Loader.require_source!("plugin/09_plugins/09_03_identity/identity.ex")
    :ok
  end

  alias Jido.AgentServer, as: Server
  alias Jido.Signal
  alias Jido.Signal.Context, as: SignalContext
  alias Jido.Examples.Plugins.Crypto
  alias Jido.Examples.Plugins.Identity.{Agent, Plugin}

  test "a private key proves identity and the Agent signs its correlated reply", %{jido: jido} do
    {peer_public, peer_private} = Crypto.peer_key_pair()
    {agent_public, _agent_private} = Crypto.agent_key_pair()

    {:ok, agent_server} =
      JidoTest.ExampleRuntime.start_agent(jido, Agent, id: unique_id("identity"))

    unsigned =
      Signal.new!(
        "examples.plugins.identity.challenge",
        %{"challenge" => "prove-control"},
        source: "/identity/peer"
      )

    assert {:ok, signed} = Crypto.sign(unsigned, peer_private, peer_public, "identity-once")

    direct = Agent.instantiate!(id: unique_id("identity-direct"))

    assert {:ok, direct, [%Jido.Agent.Directive.Reply{}]} = Jido.Agent.cmd(direct, signed)
    assert direct.state.accepted == 1
    assert direct.state.last_public_key == Base.encode16(peer_public, case: :lower)

    assert {:ok, committed, _directives} = Server.call(agent_server, signed)
    assert committed.state.accepted == 1
    assert committed.state.last_public_key == Base.encode16(peer_public, case: :lower)

    assert_receive %Signal{type: "examples.plugins.identity.accepted"} = reply
    assert {:ok, _nonce} = Crypto.verify(reply, agent_public)
    assert SignalContext.get_trace(reply).causation_id == signed.id

    assert {:error, :replayed_signal} = Server.call(agent_server, signed)
    assert Server.agent(agent_server).state.accepted == 1

    activation = Server.activation(agent_server)
    old_runtime = JidoTest.ExampleRuntime.plugin(activation, Plugin)
    old_runtime_ref = Process.monitor(old_runtime)
    Process.exit(old_runtime, :kill)
    assert_receive {:DOWN, ^old_runtime_ref, :process, ^old_runtime, :killed}

    replacement_runtime =
      eventually(fn ->
        case JidoTest.ExampleRuntime.plugin(activation, Plugin) do
          pid when is_pid(pid) and pid != old_runtime -> pid
          _child -> nil
        end
      end)

    agent_server = Jido.AgentServer.Supervisor.worker(activation)
    assert :ok = Server.await_ready(agent_server)
    assert Process.alive?(replacement_runtime)
    assert {:ok, committed, _directives} = Server.call(agent_server, signed)
    assert committed.state.accepted == 2
    assert_receive %Signal{type: "examples.plugins.identity.accepted"}

    invalid_route =
      Signal.new!(
        "examples.plugins.identity.challenge",
        %{},
        source: "/identity/peer"
      )

    assert {:ok, admitted_then_invalid} =
             Crypto.sign(
               invalid_route,
               peer_private,
               peer_public,
               "identity-invalid-route"
             )

    assert {:error, %Jido.Error.ValidationError{}} =
             Server.call(agent_server, admitted_then_invalid)

    assert {:error, :replayed_signal} = Server.call(agent_server, admitted_then_invalid)
    assert Server.agent(agent_server).state.accepted == 2

    assert {:ok, forged} =
             unsigned
             |> Map.put(:id, unique_id("forged"))
             |> Crypto.sign(peer_private, peer_public, "identity-forged")

    forged = %{forged | data: %{"challenge" => "changed-after-signing"}}
    assert {:error, :invalid_signature} = Server.call(agent_server, forged)
    assert Server.agent(agent_server).state.accepted == 2
  end
end

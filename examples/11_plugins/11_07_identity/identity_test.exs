Code.require_file("../support/crypto.ex", __DIR__)
Code.require_file("identity_plugin.ex", __DIR__)
Code.require_file("identity.ex", __DIR__)

defmodule Jido.Examples.Plugins.IdentityTest do
  use Jido.Test.Case, async: false
  @moduletag :integration

  alias Jido.AgentServer, as: Server
  alias Jido.Signal
  alias Jido.Signal.Context, as: SignalContext
  alias Jido.Examples.Plugins.Crypto
  alias Jido.Examples.Plugins.Identity.{Agent, Plugin}

  test "a private key proves identity and the Agent signs its correlated reply", %{jido: jido} do
    {peer_public, peer_private} = Crypto.peer_key_pair()
    {agent_public, _agent_private} = Crypto.agent_key_pair()

    {:ok, agent_server} =
      Jido.Test.AgentServer.ExampleRuntime.start_agent(jido, Agent, id: unique_id("identity"))

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

    assert {:ok, %Jido.AgentServer.TurnResult{status: :committed, reply: %Signal{} = reply}} =
             Server.call(agent_server, signed)

    committed = Server.snapshot(agent_server).agent
    assert committed.state.accepted == 1
    assert committed.state.last_public_key == Base.encode16(peer_public, case: :lower)

    assert reply.type == "examples.plugins.identity.accepted"
    assert {:ok, _nonce} = Crypto.verify(reply, agent_public)
    assert SignalContext.get_trace(reply).causation_id == signed.id

    assert {:ok, %Jido.AgentServer.TurnResult{status: :failed, error: :replayed_signal}} =
             Server.call(agent_server, signed)

    assert Jido.AgentServer.snapshot(agent_server).agent.state.accepted == 1

    activation = Jido.Test.AgentServer.ExampleRuntime.activation(agent_server)
    old_runtime = Jido.Test.AgentServer.ExampleRuntime.plugin(activation, Plugin)
    old_runtime_ref = Process.monitor(old_runtime)
    Process.exit(old_runtime, :kill)
    assert_receive {:DOWN, ^old_runtime_ref, :process, ^old_runtime, :killed}

    replacement_runtime =
      eventually(fn ->
        case Jido.Test.AgentServer.ExampleRuntime.plugin(activation, Plugin) do
          pid when is_pid(pid) and pid != old_runtime -> pid
          _child -> nil
        end
      end)

    agent_server = Jido.AgentServer.Supervisor.worker(activation)
    assert :ok = Jido.AgentServer.await_ready(agent_server)
    assert Process.alive?(replacement_runtime)

    assert {:ok, %Jido.AgentServer.TurnResult{status: :committed, reply: %Signal{}}} =
             Server.call(agent_server, signed)

    committed = Server.snapshot(agent_server).agent
    assert committed.state.accepted == 2

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

    assert {:ok,
            %Jido.AgentServer.TurnResult{
              status: :failed,
              error: %Jido.Error.ValidationError{}
            }} = Server.call(agent_server, admitted_then_invalid)

    assert {:ok, %Jido.AgentServer.TurnResult{status: :failed, error: :replayed_signal}} =
             Server.call(agent_server, admitted_then_invalid)

    assert Jido.AgentServer.snapshot(agent_server).agent.state.accepted == 2

    assert {:ok, forged} =
             unsigned
             |> Map.put(:id, unique_id("forged"))
             |> Crypto.sign(peer_private, peer_public, "identity-forged")

    forged = %{forged | data: %{"challenge" => "changed-after-signing"}}

    assert {:ok, %Jido.AgentServer.TurnResult{status: :failed, error: :invalid_signature}} =
             Server.call(agent_server, forged)

    assert Jido.AgentServer.snapshot(agent_server).agent.state.accepted == 2
  end
end

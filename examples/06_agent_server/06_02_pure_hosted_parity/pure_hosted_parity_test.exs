Code.require_file("pure_hosted_parity.ex", __DIR__)

defmodule Jido.Examples.AgentServer.PureHostedParityTest do
  use ExUnit.Case, async: false
  @moduletag :integration

  alias Jido.Agent.Directive.Reply
  alias Jido.AgentServer
  alias Jido.Examples.AgentServer.PureHostedParity.Counter

  setup do
    suffix = System.unique_integer([:positive])
    instance = :"pure_hosted_parity_#{suffix}"
    start_supervised!({Jido, name: instance}, id: instance)
    %{instance: instance}
  end

  test "pure and hosted execution agree on candidate state and reply data", %{instance: instance} do
    source = Counter.instantiate!(id: "parity-counter", state: %{count: 3})
    {:ok, signal} = Counter.increment_signal(%{amount: 4})

    assert {:ok, pure_candidate, [%Reply{signal: pure_reply}]} = Jido.Agent.cmd(source, signal)
    assert source.state == %{count: 3}

    assert {:ok, server} = Jido.start_agent(instance, source)
    assert :ok = AgentServer.await_ready(server)

    assert {:ok,
            %AgentServer.TurnResult{
              status: :committed,
              agent_revision: 1,
              reply: hosted_reply
            }} = AgentServer.call(server, signal)

    assert AgentServer.snapshot(server).agent == pure_candidate
    assert hosted_reply.type == pure_reply.type
    assert hosted_reply.data == pure_reply.data
    assert hosted_reply.data == %{count: 7}
    assert Jido.Signal.get_context(hosted_reply, "jidocausationid") == signal.id
  end
end

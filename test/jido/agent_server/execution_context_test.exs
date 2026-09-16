defmodule JidoTest.AgentServer.ExecutionContextTest do
  use JidoTest.Case, async: true

  alias Jido.AgentServer, as: Server
  alias Jido.Signal

  defmodule ReadContext do
    use Jido.Action, name: "execution_context_read"

    def run(_params, context) do
      send(context.observer, {:execution_context, context})
      {:ok, context.agent_state}
    end
  end

  defmodule Reader do
    use Jido.Agent,
      name: "execution_context_reader",
      routes: [{"context.read", ReadContext}]
  end

  test "a live Turn overrides caller jido and partition while a direct command keeps them", %{
    jido: jido
  } do
    {:ok, server} = Jido.start_agent(jido, Reader, partition: :blue)
    signal = Signal.new!("context.read", %{}, source: "/test")

    assert {:ok, _agent} = Server.call(server, signal, context: %{observer: self()})
    assert_receive {:execution_context, first_context}, 1_000
    assert first_context.jido == jido
    assert first_context.partition == :blue

    supplied = %{observer: self(), jido: :caller_jido, partition: :caller_partition}
    assert {:ok, _agent} = Server.call(server, signal, context: supplied)
    assert_receive {:execution_context, context}, 1_000
    assert context.jido == jido
    assert context.partition == :blue
    assert context.agent_id == Server.agent(server).id

    assert {:ok, _candidate, []} = Reader.cmd(Reader.new!(), signal, context: supplied)
    assert_receive {:execution_context, direct_context}, 1_000
    assert direct_context.jido == :caller_jido
    assert direct_context.partition == :caller_partition
  end
end

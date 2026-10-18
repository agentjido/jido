defmodule JidoTest.Examples.Research.RemoteStartTest do
  use JidoTest.Case, async: true
  @moduletag :example
  alias Jido.AgentServer, as: Server

  defmodule Owner do
    use Jido.Agent, name: "remote_rejection"

    routes do
      signal_source "/examples/research/remote"

      route "examples.research.remote.start", as: :start do
        action _input, context: context do
          directive =
            Jido.AgentServer.Directive.agent_start(
              JidoTest.Examples.Research.RemoteStartTest.Owner,
              :remote,
              node: :remote@host
            )

          {:ok, context.agent_state, [directive]}
        end
      end
    end
  end

  test "remote placement is rejected before commit", %{jido: jido} do
    {:ok, server} = JidoTest.ExampleRuntime.start_agent(jido, Owner, id: unique_id("remote"))
    assert :ok = Server.await_ready(server)
    before = Server.snapshot(server)
    assert {:ok, signal} = Owner.start_signal()
    assert {:error, _} = Server.call(server, signal)
    assert Server.snapshot(server) == before
    assert Server.children(server) == %{}
  end
end

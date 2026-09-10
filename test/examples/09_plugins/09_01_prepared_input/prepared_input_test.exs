defmodule JidoTest.Examples.Plugins.PreparedInputTest do
  use JidoTest.Case, async: true

  @moduletag :example

  alias Jido.AgentServer, as: Server
  alias Jido.Examples.Plugins.PreparedInput.Agent
  alias Jido.Signal

  test "pure preparation has direct and live parity", %{jido: jido} do
    source =
      Signal.new!("examples.plugins.prepared_input.accept", %{},
        source: "/prepared-input/test",
        subject: "tenant/ACME"
      )

    direct = Agent.new!(id: unique_id("prepared-direct"))
    assert {:ok, direct, []} = Jido.Agent.cmd(direct, source)
    assert direct.state.tenant == "acme"
    assert direct.state.last_signal_id == source.id
    assert direct.state.last_subject == source.subject

    live = Agent.new!(id: unique_id("prepared-live"))
    {:ok, server} = Jido.start_agent(jido, live)
    assert {:ok, live} = Server.call(server, source)
    assert live.state.tenant == "acme"
    assert live.state.last_signal_id == source.id
    assert live.state.last_subject == source.subject
  end

  test "preparation can reject before the route runs" do
    source =
      Signal.new!("examples.plugins.prepared_input.accept", %{}, source: "/prepared-input/test")

    agent = Agent.new!(id: unique_id("prepared-reject"))
    assert {:error, :tenant_subject_required} = Jido.Agent.cmd(agent, source)
    assert agent.state.accepted == 0
  end
end

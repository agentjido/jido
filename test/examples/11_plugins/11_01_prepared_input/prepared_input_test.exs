Code.require_file("../../support/loader.exs", __DIR__)

alias Jido.Test.Examples.Loader
Loader.require_source!("11_plugins/11_01_prepared_input/prepared_input.ex")

defmodule Jido.Examples.Plugins.PreparedInputTest do
  use Jido.Test.Case, async: true
  @moduletag :example

  setup_all do
    Jido.Test.Examples.Loader.require_source!("11_plugins/11_01_prepared_input/prepared_input.ex")
    :ok
  end

  alias Jido.AgentServer, as: Server
  alias Jido.Examples.Plugins.PreparedInput.Agent
  alias Jido.Signal

  test "pure preparation has direct and live parity", %{jido: jido} do
    source =
      Signal.new!("examples.plugins.prepared_input.accept", %{},
        source: "/prepared-input/test",
        subject: "tenant/ACME"
      )

    direct = Agent.instantiate!(id: unique_id("prepared-direct"))
    assert {:ok, direct, []} = Jido.Agent.cmd(direct, source)
    assert direct.state.tenant == "acme"
    assert direct.state.last_signal_id == source.id
    assert direct.state.last_subject == source.subject

    live = Agent.instantiate!(id: unique_id("prepared-live"))
    {:ok, server} = Jido.Test.AgentServer.ExampleRuntime.start_agent(jido, live)
    assert {:ok, live, _directives} = Server.call(server, source)
    assert live.state.tenant == "acme"
    assert live.state.last_signal_id == source.id
    assert live.state.last_subject == source.subject
  end

  test "preparation can reject before the route runs" do
    source =
      Signal.new!("examples.plugins.prepared_input.accept", %{}, source: "/prepared-input/test")

    agent = Agent.instantiate!(id: unique_id("prepared-reject"))
    assert {:error, :tenant_subject_required} = Jido.Agent.cmd(agent, source)
    assert agent.state.accepted == 0
  end
end

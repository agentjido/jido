defmodule JidoTest.Examples.Plugins.CompositionTest do
  use JidoTest.Case, async: true

  @moduletag :example

  alias Jido.AgentServer, as: Server
  alias Jido.Examples.Plugins.Composition.Agent
  alias Jido.Signal

  test "pure and live package inputs remain isolated", %{jido: jido} do
    {:ok, server} = Jido.start_agent(jido, Agent, id: unique_id("plugin-composition"))

    source =
      Signal.new!("examples.plugins.composition.accept", %{token: "allow"},
        source: "/composition/test",
        subject: "tenant/ACME"
      )

    assert {:ok, committed} = Server.call(server, source)
    assert committed.state == %{accepted: 1, owner: "acme:operator"}

    rejected = %{source | id: Jido.Signal.ID.generate!(), subject: nil}
    assert {:error, :tenant_subject_required} = Server.call(server, rejected)
    assert Server.agent(server).state == committed.state
  end
end

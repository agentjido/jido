Code.require_file("inputs.ex", __DIR__)
Code.require_file("composition.ex", __DIR__)

defmodule Jido.Examples.Plugins.CompositionTest do
  use Jido.Test.Case, async: true
  @moduletag :integration

  alias Jido.AgentServer, as: Server
  alias Jido.Examples.Plugins.Composition.Agent
  alias Jido.Signal

  test "pure and live package inputs remain isolated", %{jido: jido} do
    {:ok, server} =
      Jido.Test.AgentServer.ExampleRuntime.start_agent(jido, Agent, id: unique_id("plugin-composition"))

    source =
      Signal.new!("examples.plugins.composition.accept", %{token: "allow"},
        source: "/composition/test",
        subject: "tenant/ACME"
      )

    assert {:ok, committed, _directives} = Server.call(server, source)
    assert committed.state == %{accepted: 1, owner: "acme:operator"}

    rejected = %{source | id: unique_id("rejected"), subject: nil}
    assert {:error, :tenant_subject_required} = Server.call(server, rejected)
    assert Server.agent(server).state == committed.state
  end
end

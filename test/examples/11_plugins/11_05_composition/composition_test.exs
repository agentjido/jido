Code.require_file("../../support/loader.exs", __DIR__)

alias JidoTest.Examples.Loader
Loader.require_source!("11_plugins/11_05_composition/inputs.ex")
Loader.require_source!("11_plugins/11_05_composition/composition.ex")

defmodule JidoTest.Examples.Plugins.CompositionTest do
  use Jido.Test.Case, async: true
  @moduletag :example

  setup_all do
    JidoTest.Examples.Loader.require_source!("11_plugins/11_05_composition/composition.ex")
    :ok
  end

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

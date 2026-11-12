Code.require_file("inputs.ex", __DIR__)
Code.require_file("composition.ex", __DIR__)

defmodule Jido.Examples.Plugins.CompositionTest do
  use Jido.Test.Case, async: true
  @moduletag :integration
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

    (
      assert {:ok, %Jido.AgentServer.TurnResult{} = turn_result} =
               Jido.AgentServer.call(server, source)

      assert turn_result.status in [:committed, :waiting]
      committed = Jido.AgentServer.snapshot(server).agent
    )

    assert committed.state == %{accepted: 1, owner: "acme:operator"}

    rejected = %{source | id: unique_id("rejected"), subject: nil}

    assert {:ok, %Jido.AgentServer.TurnResult{status: :failed, error: :tenant_subject_required}} =
             Jido.AgentServer.call(server, rejected)

    assert Jido.AgentServer.snapshot(server).agent.state == committed.state
  end
end

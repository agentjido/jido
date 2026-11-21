Code.require_file("runtime_admission.ex", __DIR__)

defmodule Jido.Examples.Plugins.RuntimeAdmissionTest do
  use Jido.Test.Case, async: true
  @moduletag :integration
  alias Jido.Examples.Plugins.RuntimeAdmission.{Agent, Plugin}
  alias Jido.Signal

  test "live admission provides transient authorization", %{jido: jido} do
    source = authorization_signal("allow")

    {:ok, server} =
      Jido.Test.AgentServer.ExampleRuntime.start_agent(jido, Agent, id: unique_id("runtime-admission"))

    assert :ok = Jido.AgentServer.await_ready(server)

    (
      assert {:ok, %Jido.AgentServer.TurnResult{} = turn_result} =
               Jido.AgentServer.call(server, source)

      assert turn_result.status in [:committed, :waiting]
      committed = Jido.AgentServer.snapshot(server).agent
    )

    assert committed.state == %{accepted: 1, principal: "operator"}

    assert {:ok, %Jido.AgentServer.TurnResult{status: :failed, error: :invalid_token}} =
             Jido.AgentServer.call(server, authorization_signal("deny"))

    assert Jido.AgentServer.snapshot(server).agent.state == committed.state
  end

  test "direct cmd does not run live admission" do
    agent = Agent.instantiate!(id: unique_id("runtime-direct"))
    assert {:error, _reason} = Jido.Agent.cmd(agent, authorization_signal("allow"))
    assert agent.state == %{accepted: 0, principal: ""}
  end

  test "malformed runtime configuration fails before a child starts", %{jido: jido} do
    for tokens <- [
          nil,
          [],
          %{"allow" => "operator"},
          [{"", "operator"}],
          [{"allow", ""}],
          [{"allow", "first"}, {"allow", "second"}]
        ] do
      id = unique_id("invalid-runtime-admission")

      definition = %{
        Agent.definition()
        | plugins: [
            %{id: Plugin.id(), provider: Plugin, vsn: Plugin.vsn(), data: %{tokens: tokens}}
          ]
      }

      assert {:error,
              %Jido.Error.ValidationError{
                message: "Runtime admission tokens are invalid",
                details: %{tokens: ^tokens}
              }} = Jido.Test.AgentServer.ExampleRuntime.start_agent(jido, definition, id: id)

      assert Jido.whereis_agent(jido, id) == nil
    end
  end

  defp authorization_signal(token) do
    Signal.new!("examples.plugins.runtime_admission.accept", %{token: token}, source: "/runtime-admission/test")
  end
end

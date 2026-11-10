Code.require_file("../../support/loader.exs", __DIR__)

alias Jido.Test.Examples.Loader
Loader.require_source!("11_plugins/11_02_runtime_admission/runtime_admission.ex")

defmodule Jido.Examples.Plugins.RuntimeAdmissionTest do
  use Jido.Test.Case, async: true
  @moduletag :example

  setup_all do
    Jido.Test.Examples.Loader.require_source!("11_plugins/11_02_runtime_admission/runtime_admission.ex")
    :ok
  end

  alias Jido.AgentServer, as: Server
  alias Jido.Examples.Plugins.RuntimeAdmission.{Agent, Plugin}
  alias Jido.Signal

  test "live admission provides transient authorization", %{jido: jido} do
    source = authorization_signal("allow")

    {:ok, server} =
      Jido.Test.AgentServer.ExampleRuntime.start_agent(jido, Agent, id: unique_id("runtime-admission"))

    assert :ok = Server.await_ready(server)

    assert {:ok, committed, _directives} = Server.call(server, source)
    assert committed.state == %{accepted: 1, principal: "operator"}

    assert {:error, :invalid_token} = Server.call(server, authorization_signal("deny"))
    assert Server.agent(server).state == committed.state
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

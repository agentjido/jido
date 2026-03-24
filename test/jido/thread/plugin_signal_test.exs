defmodule JidoTest.Thread.PluginSignalTest do
  use JidoTest.Case, async: true

  alias Jido.AgentServer
  alias Jido.Thread
  alias Jido.Thread.Agent, as: ThreadAgent

  defmodule PassiveAgent do
    @moduledoc false
    use Jido.Agent,
      name: "thread_plugin_signal_agent",
      schema: []
  end

  defmodule NoThreadAgent do
    @moduledoc false
    use Jido.Agent,
      name: "thread_plugin_signal_no_thread_agent",
      default_plugins: %{__thread__: false},
      schema: []
  end

  describe "thread.entries.record" do
    test "appends entries through the default thread plugin route", %{jido: jido} do
      {:ok, pid} = Jido.start_agent(jido, PassiveAgent, id: unique_id("thread-signal"))

      {:ok, agent} =
        AgentServer.call(
          pid,
          signal("thread.entries.record", %{
            entries: [
              %{kind: :message, payload: %{role: "user", content: "late metadata"}}
            ]
          })
        )

      assert ThreadAgent.has_thread?(agent)
      thread = ThreadAgent.get(agent)
      assert Thread.entry_count(thread) == 1
      assert Thread.last(thread).payload == %{role: "user", content: "late metadata"}
    end

    test "is unavailable when the default thread plugin is disabled", %{jido: jido} do
      {:ok, pid} = Jido.start_agent(jido, NoThreadAgent, id: unique_id("thread-disabled"))

      assert {:error, %Jido.Error.RoutingError{}} =
               AgentServer.call(
                 pid,
                 signal("thread.entries.record", %{
                   entries: [
                     %{kind: :message, payload: %{role: "user", content: "ignored"}}
                   ]
                 })
               )
    end
  end
end

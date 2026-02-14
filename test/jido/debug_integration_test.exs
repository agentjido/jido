defmodule JidoTest.DebugIntegrationTest do
  use JidoTest.Case, async: false

  alias Jido.Config.Defaults
  alias Jido.Debug

  defmodule TestAgent do
    @moduledoc false
    use Jido.Agent,
      name: "debug_integration_test_agent",
      schema: [
        counter: [type: :integer, default: 0]
      ]

    def signal_routes(_ctx), do: []
  end

  setup context do
    Debug.reset(context.jido)

    on_exit(fn ->
      Debug.reset(context.jido)
    end)

    context
  end

  describe "instance-level debug enables agent recording" do
    test "debug mode enables event recording for all agents in instance", %{jido: jido} do
      pid = start_server(%{jido: jido}, TestAgent)

      {:error, :debug_not_enabled} = Jido.AgentServer.recent_events(pid)

      Debug.enable(jido, :on)

      signal = signal("jido.test.debug", %{value: 42})
      Jido.AgentServer.cast(pid, signal)

      eventually(fn ->
        {:ok, events} = Jido.AgentServer.recent_events(pid)
        assert is_list(events)
      end)
    end

    test "disabling debug stops recording", %{jido: jido} do
      Debug.enable(jido, :on)
      pid = start_server(%{jido: jido}, TestAgent)

      {:ok, _events} = Jido.AgentServer.recent_events(pid)

      Debug.disable(jido)

      {:error, :debug_not_enabled} = Jido.AgentServer.recent_events(pid)
    end
  end

  describe "debug_max_events from config" do
    test "agent state respects configured max events", %{jido: jido} do
      pid = start_server(%{jido: jido}, TestAgent, debug: true)

      {:ok, state} = Jido.AgentServer.state(pid)
      assert state.debug_max_events == Defaults.debug_max_events()
    end
  end

  describe "jido_instance in telemetry metadata" do
    test "telemetry events include jido_instance", %{jido: jido} do
      test_pid = self()
      handler_id = "test-instance-meta-#{System.unique_integer([:positive])}"

      :telemetry.attach_many(
        handler_id,
        [
          [:jido, :agent_server, :signal, :start],
          [:jido, :agent_server, :signal, :stop]
        ],
        fn _event, _measurements, metadata, _config ->
          send(test_pid, {:meta, metadata})
        end,
        nil
      )

      pid = start_server(%{jido: jido}, TestAgent)
      signal = signal("jido.test.meta", %{})
      Jido.AgentServer.cast(pid, signal)

      assert_receive {:meta, metadata}, 1000
      assert metadata[:jido_instance] == jido

      :telemetry.detach(handler_id)
    end
  end
end

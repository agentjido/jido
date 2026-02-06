defmodule JidoTest.TelemetryTest do
  use ExUnit.Case, async: false

  alias Jido.Agent
  alias Jido.Telemetry

  defmodule TestAgent do
    @moduledoc false
    use Jido.Agent,
      name: "telemetry_test_agent",
      schema: [
        counter: [type: :integer, default: 0]
      ]

    def signal_routes(_ctx), do: []
  end

  describe "start_link/1" do
    test "starts the telemetry handler" do
      try do
        :telemetry.detach("jido-agent-metrics")
      catch
        :error, _ -> :ok
      end

      case GenServer.whereis(Telemetry) do
        nil ->
          assert {:ok, pid} = Telemetry.start_link([])
          assert Process.alive?(pid)
          GenServer.stop(pid)

        existing_pid ->
          assert Process.alive?(existing_pid)
      end
    end
  end

  describe "span_agent_cmd/3" do
    setup do
      test_pid = self()
      handler_id = "test-span-agent-cmd-#{:erlang.unique_integer()}"

      :telemetry.attach_many(
        handler_id,
        [
          [:jido, :agent, :cmd, :start],
          [:jido, :agent, :cmd, :stop],
          [:jido, :agent, :cmd, :exception]
        ],
        fn event, measurements, metadata, _config ->
          send(test_pid, {:telemetry_event, event, measurements, metadata})
        end,
        nil
      )

      on_exit(fn ->
        :telemetry.detach(handler_id)
      end)

      :ok
    end

    test "emits start and stop events" do
      {:ok, agent} = Agent.new(%{id: "test-span-cmd"})

      result =
        Telemetry.span_agent_cmd(agent, :test_action, fn ->
          {agent, []}
        end)

      assert {^agent, []} = result

      assert_receive {:telemetry_event, [:jido, :agent, :cmd, :start], measurements, metadata}
      assert is_integer(measurements.system_time)
      assert metadata.agent_id == "test-span-cmd"
      assert metadata.action == :test_action

      assert_receive {:telemetry_event, [:jido, :agent, :cmd, :stop], measurements, metadata}
      assert is_integer(measurements.duration)
      assert measurements.duration >= 0
      assert metadata.directive_count == 0
    end

    test "includes directive count in stop event" do
      {:ok, agent} = Agent.new(%{id: "test-span-directives"})

      Telemetry.span_agent_cmd(agent, :test_action, fn ->
        {agent, [:directive1, :directive2, :directive3]}
      end)

      assert_receive {:telemetry_event, [:jido, :agent, :cmd, :stop], _measurements, metadata}
      assert metadata.directive_count == 3
    end

    test "emits exception event on error" do
      {:ok, agent} = Agent.new(%{id: "test-span-error"})

      assert_raise RuntimeError, "test error", fn ->
        Telemetry.span_agent_cmd(agent, :failing_action, fn ->
          raise "test error"
        end)
      end

      assert_receive {:telemetry_event, [:jido, :agent, :cmd, :start], _, _}

      assert_receive {:telemetry_event, [:jido, :agent, :cmd, :exception], measurements, metadata}
      assert is_integer(measurements.duration)
      assert metadata.kind == :error
      assert %RuntimeError{message: "test error"} = metadata.error
    end
  end

  describe "span_strategy/4" do
    setup do
      test_pid = self()
      handler_id = "test-span-strategy-#{:erlang.unique_integer()}"

      :telemetry.attach_many(
        handler_id,
        [
          [:jido, :agent, :strategy, :init, :start],
          [:jido, :agent, :strategy, :init, :stop],
          [:jido, :agent, :strategy, :init, :exception],
          [:jido, :agent, :strategy, :cmd, :start],
          [:jido, :agent, :strategy, :cmd, :stop],
          [:jido, :agent, :strategy, :cmd, :exception],
          [:jido, :agent, :strategy, :tick, :start],
          [:jido, :agent, :strategy, :tick, :stop],
          [:jido, :agent, :strategy, :tick, :exception]
        ],
        fn event, measurements, metadata, _config ->
          send(test_pid, {:telemetry_event, event, measurements, metadata})
        end,
        nil
      )

      on_exit(fn ->
        :telemetry.detach(handler_id)
      end)

      :ok
    end

    test "emits init start and stop events" do
      {:ok, agent} = Agent.new(%{id: "test-strategy-init"})

      Telemetry.span_strategy(agent, :init, TestAgent, fn ->
        {agent, []}
      end)

      assert_receive {:telemetry_event, [:jido, :agent, :strategy, :init, :start], measurements,
                      metadata}

      assert is_integer(measurements.system_time)
      assert metadata.agent_id == "test-strategy-init"
      assert metadata.strategy == TestAgent

      assert_receive {:telemetry_event, [:jido, :agent, :strategy, :init, :stop], measurements,
                      metadata}

      assert is_integer(measurements.duration)
      assert metadata.directive_count == 0
    end

    test "emits cmd start and stop events" do
      {:ok, agent} = Agent.new(%{id: "test-strategy-cmd"})

      Telemetry.span_strategy(agent, :cmd, TestAgent, fn ->
        {agent, [:d1, :d2]}
      end)

      assert_receive {:telemetry_event, [:jido, :agent, :strategy, :cmd, :start], _, metadata}
      assert metadata.strategy == TestAgent

      assert_receive {:telemetry_event, [:jido, :agent, :strategy, :cmd, :stop], _, metadata}
      assert metadata.directive_count == 2
    end

    test "emits tick start and stop events" do
      {:ok, agent} = Agent.new(%{id: "test-strategy-tick"})

      Telemetry.span_strategy(agent, :tick, TestAgent, fn ->
        :ok
      end)

      assert_receive {:telemetry_event, [:jido, :agent, :strategy, :tick, :start], _, _}
      assert_receive {:telemetry_event, [:jido, :agent, :strategy, :tick, :stop], _, _}
    end

    test "emits exception event on error" do
      {:ok, agent} = Agent.new(%{id: "test-strategy-exception"})

      assert_raise RuntimeError, "strategy error", fn ->
        Telemetry.span_strategy(agent, :cmd, TestAgent, fn ->
          raise "strategy error"
        end)
      end

      assert_receive {:telemetry_event, [:jido, :agent, :strategy, :cmd, :start], _, _}

      assert_receive {:telemetry_event, [:jido, :agent, :strategy, :cmd, :exception],
                      measurements, metadata}

      assert is_integer(measurements.duration)
      assert metadata.kind == :error
      assert %RuntimeError{message: "strategy error"} = metadata.error
    end

    test "handles non-tuple result gracefully" do
      {:ok, agent} = Agent.new(%{id: "test-strategy-non-tuple"})

      result =
        Telemetry.span_strategy(agent, :tick, TestAgent, fn ->
          :just_ok
        end)

      assert result == :just_ok

      assert_receive {:telemetry_event, [:jido, :agent, :strategy, :tick, :stop], _, metadata}
      refute Map.has_key?(metadata, :directive_count)
    end
  end

  describe "handle_event/4" do
    test "handles agent cmd start event" do
      assert :ok =
               Telemetry.handle_event(
                 [:jido, :agent, :cmd, :start],
                 %{system_time: 123},
                 %{agent_id: "test", agent_module: TestAgent, action: :test},
                 nil
               )
    end

    test "handles agent cmd stop event" do
      assert :ok =
               Telemetry.handle_event(
                 [:jido, :agent, :cmd, :stop],
                 %{duration: 1000},
                 %{agent_id: "test", agent_module: TestAgent, directive_count: 0},
                 nil
               )
    end

    test "handles agent cmd exception event" do
      assert :ok =
               Telemetry.handle_event(
                 [:jido, :agent, :cmd, :exception],
                 %{duration: 1000},
                 %{agent_id: "test", agent_module: TestAgent, error: :some_error},
                 nil
               )
    end

    test "handles strategy init events" do
      assert :ok =
               Telemetry.handle_event(
                 [:jido, :agent, :strategy, :init, :start],
                 %{system_time: 123},
                 %{agent_id: "test", strategy: TestAgent},
                 nil
               )

      assert :ok =
               Telemetry.handle_event(
                 [:jido, :agent, :strategy, :init, :stop],
                 %{duration: 1000},
                 %{agent_id: "test", strategy: TestAgent},
                 nil
               )

      assert :ok =
               Telemetry.handle_event(
                 [:jido, :agent, :strategy, :init, :exception],
                 %{duration: 1000},
                 %{agent_id: "test", strategy: TestAgent, error: :err},
                 nil
               )
    end

    test "handles strategy cmd events" do
      assert :ok =
               Telemetry.handle_event(
                 [:jido, :agent, :strategy, :cmd, :start],
                 %{system_time: 123},
                 %{agent_id: "test", strategy: TestAgent},
                 nil
               )

      assert :ok =
               Telemetry.handle_event(
                 [:jido, :agent, :strategy, :cmd, :stop],
                 %{duration: 1000},
                 %{agent_id: "test", strategy: TestAgent, directive_count: 2},
                 nil
               )

      assert :ok =
               Telemetry.handle_event(
                 [:jido, :agent, :strategy, :cmd, :exception],
                 %{duration: 1000},
                 %{agent_id: "test", strategy: TestAgent, error: :err},
                 nil
               )
    end

    test "handles strategy tick events" do
      assert :ok =
               Telemetry.handle_event(
                 [:jido, :agent, :strategy, :tick, :start],
                 %{system_time: 123},
                 %{agent_id: "test", strategy: TestAgent},
                 nil
               )

      assert :ok =
               Telemetry.handle_event(
                 [:jido, :agent, :strategy, :tick, :stop],
                 %{duration: 1000},
                 %{agent_id: "test", strategy: TestAgent},
                 nil
               )

      assert :ok =
               Telemetry.handle_event(
                 [:jido, :agent, :strategy, :tick, :exception],
                 %{duration: 1000},
                 %{agent_id: "test", strategy: TestAgent, error: :err},
                 nil
               )
    end

    test "handles agent_server signal events" do
      assert :ok =
               Telemetry.handle_event(
                 [:jido, :agent_server, :signal, :start],
                 %{system_time: 123},
                 %{agent_id: "test", signal_type: "test.signal"},
                 nil
               )

      assert :ok =
               Telemetry.handle_event(
                 [:jido, :agent_server, :signal, :stop],
                 %{duration: 1000},
                 %{agent_id: "test", signal_type: "test.signal", directive_count: 1},
                 nil
               )

      assert :ok =
               Telemetry.handle_event(
                 [:jido, :agent_server, :signal, :exception],
                 %{duration: 1000},
                 %{agent_id: "test", signal_type: "test.signal", error: :err},
                 nil
               )
    end

    test "handles agent_server directive events" do
      assert :ok =
               Telemetry.handle_event(
                 [:jido, :agent_server, :directive, :start],
                 %{system_time: 123},
                 %{agent_id: "test", directive_type: "Emit"},
                 nil
               )

      assert :ok =
               Telemetry.handle_event(
                 [:jido, :agent_server, :directive, :stop],
                 %{duration: 1000},
                 %{agent_id: "test", directive_type: "Emit", result: :ok},
                 nil
               )

      assert :ok =
               Telemetry.handle_event(
                 [:jido, :agent_server, :directive, :exception],
                 %{duration: 1000},
                 %{agent_id: "test", directive_type: "Emit", error: :err},
                 nil
               )
    end

    test "handles queue overflow event" do
      assert :ok =
               Telemetry.handle_event(
                 [:jido, :agent_server, :queue, :overflow],
                 %{queue_size: 100},
                 %{agent_id: "test", signal_type: "test.signal"},
                 nil
               )
    end
  end
end

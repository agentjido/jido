defmodule JidoTest.AgentServer.TelemetryTest do
  use JidoTest.Case, async: false

  import ExUnit.CaptureLog

  alias Jido.Agent.Directive
  alias Jido.AgentServer
  alias Jido.Debug
  alias Jido.Signal
  alias JidoTest.TestActions

  defmodule EmitDirectiveAction do
    @moduledoc false
    use Jido.Action, name: "emit_directive", schema: []

    def run(_params, _context) do
      signal = Signal.new!("test.emitted", %{}, source: "/test")
      {:ok, %{}, [%Directive.Emit{signal: signal}]}
    end
  end

  defmodule ScheduleDirectiveAction do
    @moduledoc false
    use Jido.Action, name: "schedule_directive", schema: []

    def run(_params, _context) do
      {:ok, %{}, [%Directive.Schedule{delay_ms: 100, message: :tick}]}
    end
  end

  defmodule TelemetryAgent do
    @moduledoc false
    use Jido.Agent,
      name: "telemetry_agent",
      schema: [
        counter: [type: :integer, default: 0]
      ]

    def signal_routes(_ctx) do
      [
        {"increment", TestActions.IncrementAction},
        {"emit_directive", EmitDirectiveAction},
        {"schedule_directive", ScheduleDirectiveAction}
      ]
    end
  end

  setup context do
    test_pid = self()

    handler_id = "test-telemetry-handler-#{:erlang.unique_integer()}"

    :telemetry.attach_many(
      handler_id,
      [
        [:jido, :agent_server, :signal, :start],
        [:jido, :agent_server, :signal, :stop],
        [:jido, :agent_server, :signal, :exception],
        [:jido, :agent_server, :directive, :start],
        [:jido, :agent_server, :directive, :stop],
        [:jido, :agent_server, :directive, :exception],
        [:jido, :agent_server, :queue, :overflow]
      ],
      fn event, measurements, metadata, _config ->
        send(test_pid, {:telemetry_event, event, measurements, metadata})
      end,
      nil
    )

    action_handler_id = "test-action-telemetry-handler-#{:erlang.unique_integer()}"

    :telemetry.attach_many(
      action_handler_id,
      [
        [:jido, :action, :start],
        [:jido, :action, :stop]
      ],
      fn event, measurements, metadata, _config ->
        send(test_pid, {:action_telemetry_event, event, measurements, metadata})
      end,
      nil
    )

    on_exit(fn ->
      :telemetry.detach(handler_id)
      :telemetry.detach(action_handler_id)
    end)

    {:ok, jido: context.jido}
  end

  describe "signal telemetry" do
    test "emits start and stop events for signal processing", %{jido: jido} do
      {:ok, pid} =
        AgentServer.start_link(agent: TelemetryAgent, id: "telemetry-signal-test", jido: jido)

      signal = Signal.new!("increment", %{}, source: "/test")
      {:ok, _agent} = AgentServer.call(pid, signal)

      assert_receive {:telemetry_event, [:jido, :agent_server, :signal, :start], measurements,
                      metadata}

      assert is_integer(measurements.system_time)
      assert metadata.agent_id == "telemetry-signal-test"
      assert metadata.signal_type == "increment"

      assert_receive {:telemetry_event, [:jido, :agent_server, :signal, :stop], measurements,
                      metadata}

      assert is_integer(measurements.duration)
      assert measurements.duration >= 0
      assert metadata.directive_count == 0

      GenServer.stop(pid)
    end

    test "includes directive count in stop event", %{jido: jido} do
      {:ok, pid} =
        AgentServer.start_link(agent: TelemetryAgent, id: "telemetry-directive-count", jido: jido)

      signal = Signal.new!("emit_directive", %{}, source: "/test")
      {:ok, _agent} = AgentServer.call(pid, signal)

      assert_receive {:telemetry_event, [:jido, :agent_server, :signal, :start], _, _}

      assert_receive {:telemetry_event, [:jido, :agent_server, :signal, :stop], _, metadata}

      assert metadata.directive_count == 1
      assert metadata.directive_types == %{"Emit" => 1}

      GenServer.stop(pid)
    end
  end

  describe "action logging integration" do
    test "suppresses jido_action start logs when args are not full", %{jido: jido} do
      {:ok, pid} =
        AgentServer.start_link(agent: TelemetryAgent, id: "telemetry-log-default", jido: jido)

      signal = Signal.new!("increment", %{}, source: "/test")

      log =
        capture_log(fn ->
          assert {:ok, _agent} = AgentServer.call(pid, signal)
        end)

      refute log =~ "Executing JidoTest.TestActions.IncrementAction"
      refute log =~ "with params:"
      refute_receive {:action_telemetry_event, [:jido, :action, :start], _, _}, 50

      GenServer.stop(pid)
    end

    test "enables verbose jido_action logs when instance debug is verbose", %{jido: jido} do
      Debug.enable(jido, :verbose)
      on_exit(fn -> Debug.disable(jido) end)

      {:ok, pid} =
        AgentServer.start_link(agent: TelemetryAgent, id: "telemetry-log-verbose", jido: jido)

      signal = Signal.new!("increment", %{}, source: "/test")

      log =
        capture_log(fn ->
          assert {:ok, _agent} = AgentServer.call(pid, signal)
        end)

      assert log =~ "Executing JidoTest.TestActions.IncrementAction"
      assert log =~ "with params:"

      assert_receive {:action_telemetry_event, [:jido, :action, :start], _,
                      %{action: JidoTest.TestActions.IncrementAction}}

      assert_receive {:action_telemetry_event, [:jido, :action, :stop], _, _}

      GenServer.stop(pid)
    end
  end

  describe "directive telemetry" do
    test "emits start and stop events for directive execution", %{jido: jido} do
      {:ok, pid} =
        AgentServer.start_link(agent: TelemetryAgent, id: "telemetry-directive-test", jido: jido)

      signal = Signal.new!("emit_directive", %{}, source: "/test")
      {:ok, _agent} = AgentServer.call(pid, signal)

      # Signal events
      assert_receive {:telemetry_event, [:jido, :agent_server, :signal, :start], _, _}
      assert_receive {:telemetry_event, [:jido, :agent_server, :signal, :stop], _, _}

      assert_receive {:telemetry_event, [:jido, :agent_server, :directive, :start], measurements,
                      %{agent_id: "telemetry-directive-test", directive_type: "Emit"} = metadata},
                     500

      assert is_integer(measurements.system_time)
      assert metadata.signal_type == "emit_directive"
      assert match?(%Directive.Emit{}, metadata.directive)

      assert_receive {:telemetry_event, [:jido, :agent_server, :directive, :stop], measurements,
                      %{agent_id: "telemetry-directive-test", result: :async} = metadata},
                     500

      assert is_integer(measurements.duration)
      assert metadata.signal_type == "emit_directive"
      assert match?(%Directive.Emit{}, metadata.directive)

      GenServer.stop(pid)
    end

    test "reports correct directive type", %{jido: jido} do
      {:ok, pid} =
        AgentServer.start_link(agent: TelemetryAgent, id: "telemetry-type-test", jido: jido)

      signal = Signal.new!("schedule_directive", %{}, source: "/test")
      {:ok, _agent} = AgentServer.call(pid, signal)

      # Skip signal events
      assert_receive {:telemetry_event, [:jido, :agent_server, :signal, :start], _, _}
      assert_receive {:telemetry_event, [:jido, :agent_server, :signal, :stop], _, _}

      assert_receive {:telemetry_event, [:jido, :agent_server, :directive, :start], _,
                      %{directive_type: "Schedule", signal_type: "schedule_directive"} = metadata},
                     500

      assert match?(%Directive.Schedule{}, metadata.directive)

      assert_receive {:telemetry_event, [:jido, :agent_server, :directive, :stop], _,
                      %{result: :ok, signal_type: "schedule_directive"} = metadata},
                     500

      assert match?(%Directive.Schedule{}, metadata.directive)

      GenServer.stop(pid)
    end
  end

  describe "metadata correctness" do
    test "includes agent_id and agent_module in signal events", %{jido: jido} do
      {:ok, pid} =
        AgentServer.start_link(agent: TelemetryAgent, id: "telemetry-metadata-test", jido: jido)

      signal = Signal.new!("increment", %{}, source: "/test")
      {:ok, _agent} = AgentServer.call(pid, signal)

      assert_receive {:telemetry_event, [:jido, :agent_server, :signal, :start], _, metadata}

      assert metadata.agent_id == "telemetry-metadata-test"
      assert metadata.agent_module == TelemetryAgent
      assert metadata.signal_type == "increment"

      GenServer.stop(pid)
    end

    test "includes signal_type in directive events", %{jido: jido} do
      {:ok, pid} =
        AgentServer.start_link(
          agent: TelemetryAgent,
          id: "telemetry-signal-type-test",
          jido: jido
        )

      signal = Signal.new!("emit_directive", %{}, source: "/test")
      {:ok, _agent} = AgentServer.call(pid, signal)

      # Skip signal events
      assert_receive {:telemetry_event, [:jido, :agent_server, :signal, :start], _, _}
      assert_receive {:telemetry_event, [:jido, :agent_server, :signal, :stop], _, _}

      assert_receive {:telemetry_event, [:jido, :agent_server, :directive, :start], _,
                      %{signal_type: "emit_directive", directive_type: "Emit"}},
                     500

      GenServer.stop(pid)
    end
  end

  describe "timing measurements" do
    test "duration is positive for signal processing", %{jido: jido} do
      {:ok, pid} =
        AgentServer.start_link(agent: TelemetryAgent, id: "telemetry-timing-test", jido: jido)

      signal = Signal.new!("increment", %{}, source: "/test")
      {:ok, _agent} = AgentServer.call(pid, signal)

      assert_receive {:telemetry_event, [:jido, :agent_server, :signal, :stop], measurements, _}

      assert measurements.duration >= 0

      GenServer.stop(pid)
    end

    test "duration is positive for directive execution", %{jido: jido} do
      {:ok, pid} =
        AgentServer.start_link(
          agent: TelemetryAgent,
          id: "telemetry-directive-timing",
          jido: jido
        )

      signal = Signal.new!("emit_directive", %{}, source: "/test")
      {:ok, _agent} = AgentServer.call(pid, signal)

      # Skip signal events
      assert_receive {:telemetry_event, [:jido, :agent_server, :signal, :start], _, _}
      assert_receive {:telemetry_event, [:jido, :agent_server, :signal, :stop], _, _}

      assert_receive {:telemetry_event, [:jido, :agent_server, :directive, :stop], measurements,
                      %{signal_type: "emit_directive", result: :async}},
                     500

      assert measurements.duration >= 0

      GenServer.stop(pid)
    end
  end
end

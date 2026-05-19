defmodule JidoTest.AgentServer.TelemetryTest do
  use JidoTest.Case, async: false

  import ExUnit.CaptureLog

  alias Jido.Agent.Directive
  alias Jido.AgentServer
  alias Jido.Debug
  alias Jido.Instruction
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

  defmodule FallbackExecStrategy do
    @moduledoc false
    use Jido.Agent.Strategy

    @impl true
    def cmd(agent, instructions, _ctx) do
      send_instruction_opts(agent, instructions)
      Enum.each(instructions, &Jido.Exec.run/1)
      {agent, []}
    end

    defp send_instruction_opts(%{state: %{observer_pid: pid}}, instructions) when is_pid(pid) do
      send(pid, {:fallback_exec_instruction_opts, Enum.map(instructions, & &1.opts)})
    end

    defp send_instruction_opts(_agent, _instructions), do: :ok
  end

  defmodule FallbackExecAgent do
    @moduledoc false
    use Jido.Agent,
      name: "fallback_exec_agent",
      schema: [
        observer_pid: [type: :any, default: nil]
      ],
      strategy: FallbackExecStrategy

    def signal_routes(_ctx) do
      [{"fallback_exec", JidoTest.TestActions.IncrementAction}]
    end
  end

  defmodule InspectOptsStrategy do
    @moduledoc false
    use Jido.Agent.Strategy

    @impl true
    def cmd(agent, instructions, _ctx) do
      send(
        agent.state.observer_pid,
        {:inspect_instruction_opts, Enum.map(instructions, & &1.opts)}
      )

      {agent, []}
    end
  end

  defmodule InspectOptsAgent do
    @moduledoc false
    use Jido.Agent,
      name: "inspect_opts_agent",
      schema: [
        observer_pid: [type: :any, default: nil]
      ],
      strategy: InspectOptsStrategy
  end

  defmodule RaisingStrategy do
    @moduledoc false
    use Jido.Agent.Strategy

    @impl true
    def cmd(_agent, _instructions, _ctx), do: raise("signal exploded")
  end

  defmodule RaisingAgent do
    @moduledoc false
    use Jido.Agent,
      name: "raising_agent",
      schema: [],
      strategy: RaisingStrategy

    def signal_routes(_ctx), do: [{"explode", JidoTest.TestActions.IncrementAction}]
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

    test "emits bounded public metadata for signal exceptions", %{jido: jido} do
      {:ok, pid} =
        AgentServer.start_link(agent: RaisingAgent, id: "telemetry-signal-error", jido: jido)

      signal = Signal.new!("explode", %{}, source: "/test")

      capture_log(fn ->
        assert {:error, %RuntimeError{message: "signal exploded"}} = AgentServer.call(pid, signal)
      end)

      assert_receive {:telemetry_event, [:jido, :agent_server, :signal, :start], _, _}

      assert_receive {:telemetry_event, [:jido, :agent_server, :signal, :exception], measurements,
                      metadata}

      assert is_integer(measurements.duration)
      assert metadata.agent_id == "telemetry-signal-error"
      assert metadata.signal_type == "explode"
      assert metadata.kind == :error

      assert %{type: :internal, message: "signal exploded", details: %{}, retryable?: true} =
               metadata.error

      assert metadata.error_type == :internal
      assert metadata.retryable? == true
      refute Map.has_key?(metadata, :stacktrace)

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

    test "passes quiet action exec opts to custom strategies", %{jido: jido} do
      {:ok, pid} =
        AgentServer.start_link(
          agent: FallbackExecAgent,
          id: "telemetry-custom-strategy",
          initial_state: %{observer_pid: self()},
          jido: jido
        )

      signal = Signal.new!("fallback_exec", %{}, source: "/test")

      log =
        capture_log(fn ->
          assert {:ok, _agent} = AgentServer.call(pid, signal)
        end)

      refute log =~ "Executing JidoTest.TestActions.IncrementAction"
      refute log =~ "with params:"

      assert_receive {:fallback_exec_instruction_opts, [opts]}
      assert Keyword.get(opts, :log_level) == :warning
      assert Keyword.get(opts, :telemetry) == :silent

      refute_receive {:action_telemetry_event, [:jido, :action, :start], _, _}, 50

      GenServer.stop(pid)
    end

    test "preserves explicit instruction opts when applying action exec defaults" do
      agent = InspectOptsAgent.new(state: %{observer_pid: self()})

      instruction = %Instruction{
        action: TestActions.IncrementAction,
        opts: [log_level: :info, telemetry: :full, timeout: 100]
      }

      assert {_agent, []} =
               InspectOptsAgent.cmd(agent, instruction,
                 __jido_action_exec_defaults__: [log_level: :warning, telemetry: :silent]
               )

      assert_receive {:inspect_instruction_opts,
                      [[log_level: :info, telemetry: :full, timeout: 100]]}
    end

    test "applies action exec defaults without requiring keyword instruction opts" do
      agent = InspectOptsAgent.new(state: %{observer_pid: self()})

      instruction = %Instruction{
        action: TestActions.IncrementAction,
        opts: [:custom_flag]
      }

      assert {_agent, []} =
               InspectOptsAgent.cmd(agent, instruction,
                 __jido_action_exec_defaults__: [log_level: :warning, telemetry: :silent]
               )

      assert_receive {:inspect_instruction_opts, [opts]}
      assert Keyword.get(opts, :log_level) == :warning
      assert Keyword.get(opts, :telemetry) == :silent
      assert :custom_flag in opts
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

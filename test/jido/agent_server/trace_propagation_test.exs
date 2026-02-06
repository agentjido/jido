defmodule JidoTest.AgentServer.TracePropagationTest do
  use JidoTest.Case, async: false

  alias Jido.Agent.Directive
  alias Jido.AgentServer
  alias Jido.Signal
  alias Jido.Tracing.Trace
  alias JidoTest.TestActions

  defmodule EmitAction do
    @moduledoc false
    use Jido.Action, name: "emit", schema: []

    def run(_params, _context) do
      signal = Signal.new!("test.emitted", %{value: 42}, source: "/test")
      {:ok, %{}, [%Directive.Emit{signal: signal}]}
    end
  end

  defmodule TracedAgent do
    @moduledoc false
    use Jido.Agent,
      name: "traced_agent",
      schema: [
        counter: [type: :integer, default: 0],
        received_signals: [type: {:list, :any}, default: []]
      ]

    def signal_routes(_ctx) do
      [
        {"increment", TestActions.IncrementAction},
        {"emit", EmitAction}
      ]
    end
  end

  describe "signal ingress tracing" do
    test "signal without trace gets root trace added", context do
      test_pid = self()
      handler_id = "trace-ingress-test-#{:erlang.unique_integer()}"

      :telemetry.attach(
        handler_id,
        [:jido, :agent_server, :signal, :start],
        fn _event, _measurements, metadata, _config ->
          send(test_pid, {:telemetry, metadata})
        end,
        nil
      )

      {:ok, pid} = AgentServer.start_link(agent: TracedAgent, jido: context.jido)
      signal = Signal.new!("increment", %{}, source: "/test")

      assert Trace.get(signal) == nil

      {:ok, _agent} = AgentServer.call(pid, signal)

      assert_receive {:telemetry, metadata}, 1000
      assert is_binary(metadata[:jido_trace_id])
      assert is_binary(metadata[:jido_span_id])

      :telemetry.detach(handler_id)
      GenServer.stop(pid)
    end

    test "signal with existing trace preserves trace_id", context do
      test_pid = self()
      handler_id = "trace-preserve-test-#{:erlang.unique_integer()}"

      :telemetry.attach(
        handler_id,
        [:jido, :agent_server, :signal, :start],
        fn _event, _measurements, metadata, _config ->
          send(test_pid, {:telemetry, metadata})
        end,
        nil
      )

      {:ok, pid} = AgentServer.start_link(agent: TracedAgent, jido: context.jido)

      ctx = Trace.new_root()
      signal = Signal.new!("increment", %{}, source: "/test")
      {:ok, traced_signal} = Trace.put(signal, ctx)

      {:ok, _agent} = AgentServer.call(pid, traced_signal)

      assert_receive {:telemetry, metadata}, 1000
      assert metadata[:jido_trace_id] == ctx.trace_id
      assert metadata[:jido_span_id] == ctx.span_id

      :telemetry.detach(handler_id)
      GenServer.stop(pid)
    end
  end

  describe "directive trace propagation" do
    test "emit directive adds child trace to emitted signal", context do
      test_pid = self()
      handler_id = "trace-emit-test-#{:erlang.unique_integer()}"

      :telemetry.attach(
        handler_id,
        [:jido, :agent_server, :directive, :start],
        fn _event, _measurements, metadata, _config ->
          if metadata[:directive_type] == "Emit" do
            send(test_pid, {:telemetry, metadata})
          end
        end,
        nil
      )

      {:ok, pid} = AgentServer.start_link(agent: TracedAgent, jido: context.jido)

      ctx = Trace.new_root()
      signal = Signal.new!("emit", %{}, source: "/test")
      {:ok, traced_signal} = Trace.put(signal, ctx)

      {:ok, _agent} = AgentServer.call(pid, traced_signal)

      assert_receive {:telemetry, metadata}, 1000
      assert metadata[:jido_trace_id] == ctx.trace_id

      :telemetry.detach(handler_id)
      GenServer.stop(pid)
    end
  end

  describe "telemetry trace metadata" do
    test "signal telemetry includes all trace fields", context do
      test_pid = self()
      handler_id = "trace-metadata-test-#{:erlang.unique_integer()}"

      :telemetry.attach(
        handler_id,
        [:jido, :agent_server, :signal, :start],
        fn _event, _measurements, metadata, _config ->
          send(test_pid, {:telemetry, metadata})
        end,
        nil
      )

      {:ok, pid} = AgentServer.start_link(agent: TracedAgent, jido: context.jido)

      parent_ctx = Trace.new_root()
      child_ctx = Trace.child_of(parent_ctx, "parent-signal-id")
      signal = Signal.new!("increment", %{}, source: "/test")
      {:ok, traced_signal} = Trace.put(signal, child_ctx)

      {:ok, _agent} = AgentServer.call(pid, traced_signal)

      assert_receive {:telemetry, metadata}, 1000
      assert metadata[:jido_trace_id] == parent_ctx.trace_id
      assert metadata[:jido_span_id] == child_ctx.span_id
      assert metadata[:jido_parent_span_id] == parent_ctx.span_id
      assert metadata[:jido_causation_id] == "parent-signal-id"

      :telemetry.detach(handler_id)
      GenServer.stop(pid)
    end

    test "directive telemetry includes trace fields", context do
      test_pid = self()
      handler_id = "trace-directive-metadata-#{:erlang.unique_integer()}"

      :telemetry.attach(
        handler_id,
        [:jido, :agent_server, :directive, :start],
        fn _event, _measurements, metadata, _config ->
          send(test_pid, {:telemetry, metadata})
        end,
        nil
      )

      {:ok, pid} = AgentServer.start_link(agent: TracedAgent, jido: context.jido)

      ctx = Trace.new_root()
      signal = Signal.new!("emit", %{}, source: "/test")
      {:ok, traced_signal} = Trace.put(signal, ctx)

      {:ok, _agent} = AgentServer.call(pid, traced_signal)

      assert_receive {:telemetry, metadata}, 1000
      assert metadata[:jido_trace_id] == ctx.trace_id
      assert metadata[:jido_span_id] == ctx.span_id

      :telemetry.detach(handler_id)
      GenServer.stop(pid)
    end
  end
end

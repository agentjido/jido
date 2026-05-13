defmodule JidoTest.AgentServer.PluginPrepareHooksTest do
  use JidoTest.Case, async: true

  alias Jido.Agent.Directive
  alias Jido.Agent.StateOp
  alias Jido.Signal

  defmodule RecordTrustedContextAction do
    @moduledoc false

    use Jido.Action,
      name: "record_trusted_context",
      schema: Zoi.object(%{payload: Zoi.string()})

    @impl true
    def run(params, context) do
      {:ok, %{},
       %StateOp.SetState{
         attrs: %{
           trusted_principal_id: context.identity.principal_id,
           prepared_signal_type: context.signal.type,
           payload: params.payload,
           params_contain_principal?: Map.has_key?(params, :principal_id)
         }
       }}
    end
  end

  defmodule EmitRawSignalAction do
    @moduledoc false

    use Jido.Action,
      name: "emit_raw_signal",
      schema: Zoi.object(%{})

    @impl true
    def run(_params, _context) do
      signal = Signal.new!("outbound.raw", %{payload: "raw"}, source: "/test")
      {:ok, %{}, %Directive.Emit{signal: signal}}
    end
  end

  defmodule RecordPreparedEmitAction do
    @moduledoc false

    use Jido.Action,
      name: "record_prepared_emit",
      schema: Zoi.object(%{payload: Zoi.string(), had_correlation?: Zoi.boolean()})

    @impl true
    def run(params, context) do
      {:ok, %{},
       %StateOp.SetState{
         attrs: %{
           emitted_signal_type: context.signal.type,
           emitted_payload: params.payload,
           emitted_had_correlation?: params.had_correlation?
         }
       }}
    end
  end

  defmodule TrustedIdentityPlugin do
    @moduledoc false

    use Jido.Plugin,
      name: "trusted_identity",
      state_key: :trusted_identity,
      actions: [],
      signal_patterns: []

    @impl true
    def handle_signal(%Signal{type: "incoming.original"} = signal, _context) do
      rewritten = %{signal | type: "incoming.rewritten", data: %{payload: "rewritten"}}
      {:ok, {:continue, rewritten}}
    end

    def handle_signal(signal, _context), do: {:ok, {:continue, signal}}

    @impl true
    def prepare_action(%Signal{type: "incoming.rewritten"} = signal, _context) do
      {:ok, signal, %{identity: %{principal_id: "agent_trusted"}}}
    end

    def prepare_action(signal, _context), do: {:ok, signal, %{}}
  end

  defmodule ReservedContextPlugin do
    @moduledoc false

    use Jido.Plugin,
      name: "reserved_context",
      state_key: :reserved_context,
      actions: [],
      signal_patterns: []

    @impl true
    def prepare_action(signal, _context), do: {:ok, signal, %{state: :forbidden}}
  end

  defmodule DuplicateContextPluginA do
    @moduledoc false

    use Jido.Plugin,
      name: "duplicate_context_a",
      state_key: :duplicate_context_a,
      actions: [],
      signal_patterns: []

    @impl true
    def prepare_action(signal, _context), do: {:ok, signal, %{identity: %{principal_id: "a"}}}
  end

  defmodule DuplicateContextPluginB do
    @moduledoc false

    use Jido.Plugin,
      name: "duplicate_context_b",
      state_key: :duplicate_context_b,
      actions: [],
      signal_patterns: []

    @impl true
    def prepare_action(signal, _context), do: {:ok, signal, %{identity: %{principal_id: "b"}}}
  end

  defmodule PrepareEmitPlugin do
    @moduledoc false

    use Jido.Plugin,
      name: "prepare_emit",
      state_key: :prepare_emit,
      actions: [],
      signal_patterns: []

    @impl true
    def prepare_emit(%Signal{type: "outbound.raw"} = signal, _context) do
      {:ok,
       %{
         signal
         | type: "outbound.prepared",
           data: %{
             payload: "prepared",
             had_correlation?: Map.has_key?(signal.extensions, "correlation")
           }
       }}
    end

    def prepare_emit(signal, _context), do: {:ok, signal}
  end

  defmodule RejectEmitPlugin do
    @moduledoc false

    use Jido.Plugin,
      name: "reject_emit",
      state_key: :reject_emit,
      actions: [],
      signal_patterns: []

    @impl true
    def prepare_emit(%Signal{type: "outbound.raw"}, _context), do: {:error, :blocked_emit}
    def prepare_emit(signal, _context), do: {:ok, signal}
  end

  defmodule TrustedAgent do
    @moduledoc false

    use Jido.Agent,
      name: "trusted_agent",
      schema: [
        trusted_principal_id: [type: :string, default: nil],
        prepared_signal_type: [type: :string, default: nil],
        payload: [type: :string, default: nil],
        params_contain_principal?: [type: :boolean, default: nil]
      ],
      plugins: [TrustedIdentityPlugin]

    def signal_routes(_ctx), do: [{"incoming.rewritten", RecordTrustedContextAction}]
  end

  defmodule ReservedContextAgent do
    @moduledoc false

    use Jido.Agent,
      name: "reserved_context_agent",
      plugins: [ReservedContextPlugin]

    def signal_routes(_ctx), do: [{"incoming.rewritten", RecordTrustedContextAction}]
  end

  defmodule DuplicateContextAgent do
    @moduledoc false

    use Jido.Agent,
      name: "duplicate_context_agent",
      plugins: [DuplicateContextPluginA, DuplicateContextPluginB]

    def signal_routes(_ctx), do: [{"incoming.rewritten", RecordTrustedContextAction}]
  end

  defmodule EmitAgent do
    @moduledoc false

    use Jido.Agent,
      name: "emit_agent",
      schema: [
        emitted_signal_type: [type: :string, default: nil],
        emitted_payload: [type: :string, default: nil],
        emitted_had_correlation?: [type: :boolean, default: nil]
      ],
      plugins: [PrepareEmitPlugin]

    def signal_routes(_ctx) do
      [
        {"emit.start", EmitRawSignalAction},
        {"outbound.prepared", RecordPreparedEmitAction}
      ]
    end
  end

  defmodule RejectEmitAgent do
    @moduledoc false

    use Jido.Agent,
      name: "reject_emit_agent",
      schema: [
        emitted_signal_type: [type: :string, default: nil],
        emitted_payload: [type: :string, default: nil],
        emitted_had_correlation?: [type: :boolean, default: nil]
      ],
      plugins: [RejectEmitPlugin]

    def signal_routes(_ctx) do
      [
        {"emit.start", EmitRawSignalAction},
        {"outbound.raw", RecordPreparedEmitAction}
      ]
    end
  end

  describe "prepare_action/2" do
    test "receives rewritten signal and contributes trusted context without changing params", %{
      jido: jido
    } do
      {:ok, pid} = Jido.AgentServer.start_link(agent: TrustedAgent, jido: jido)

      signal = Signal.new!("incoming.original", %{payload: "original"}, source: "/test")
      {:ok, agent} = Jido.AgentServer.call(pid, signal)

      assert agent.state.trusted_principal_id == "agent_trusted"
      assert agent.state.prepared_signal_type == "incoming.rewritten"
      assert agent.state.payload == "rewritten"
      assert agent.state.params_contain_principal? == false
    end

    test "runs on async signal path", %{jido: jido} do
      {:ok, pid} = Jido.AgentServer.start_link(agent: TrustedAgent, jido: jido)

      signal = Signal.new!("incoming.original", %{payload: "original"}, source: "/test")
      :ok = Jido.AgentServer.cast(pid, signal)

      state =
        eventually_state(pid, fn state ->
          state.agent.state.trusted_principal_id == "agent_trusted"
        end)

      assert state.agent.state.prepared_signal_type == "incoming.rewritten"
    end

    test "reserved context keys fail closed", %{jido: jido} do
      {:ok, pid} = Jido.AgentServer.start_link(agent: ReservedContextAgent, jido: jido)

      signal = Signal.new!("incoming.rewritten", %{payload: "x"}, source: "/test")
      assert {:error, error} = Jido.AgentServer.call(pid, signal)
      assert Exception.message(error) =~ "reserved context keys"
    end

    test "duplicate context keys fail closed", %{jido: jido} do
      {:ok, pid} = Jido.AgentServer.start_link(agent: DuplicateContextAgent, jido: jido)

      signal = Signal.new!("incoming.rewritten", %{payload: "x"}, source: "/test")
      assert {:error, error} = Jido.AgentServer.call(pid, signal)
      assert Exception.message(error) =~ "duplicate context keys"
    end
  end

  describe "prepare_emit/2" do
    test "rewrites emitted signals before dispatch", %{jido: jido} do
      {:ok, pid} = Jido.AgentServer.start_link(agent: EmitAgent, jido: jido)

      signal = Signal.new!("emit.start", %{}, source: "/test")
      {:ok, _agent} = Jido.AgentServer.call(pid, signal)

      state =
        eventually_state(pid, fn state ->
          state.agent.state.emitted_signal_type == "outbound.prepared"
        end)

      assert state.agent.state.emitted_payload == "prepared"
      assert state.agent.state.emitted_had_correlation? == true
    end

    test "errors fail closed through the configured error policy", %{jido: jido} do
      parent = self()

      error_policy = fn directive, state ->
        send(parent, {:prepare_emit_error, directive.context, directive.error})
        {:ok, state}
      end

      {:ok, pid} =
        Jido.AgentServer.start_link(
          agent: RejectEmitAgent,
          jido: jido,
          error_policy: error_policy
        )

      signal = Signal.new!("emit.start", %{}, source: "/test")
      assert {:ok, _agent} = Jido.AgentServer.call(pid, signal)

      assert_receive {:prepare_emit_error, :plugin_prepare_emit, error}, 500
      assert Exception.message(error) =~ "Plugin prepare_emit failed"

      {:ok, state} = Jido.AgentServer.state(pid)
      assert state.agent.state.emitted_signal_type == nil
    end
  end
end

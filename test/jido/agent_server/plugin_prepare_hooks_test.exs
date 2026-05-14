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
           trusted_scope: context.authorization.scope,
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
      {:ok, %{}, %Directive.Emit{signal: signal, dispatch: {:logger, level: :info}}}
    end
  end

  defmodule RecordPreparedEmitAction do
    @moduledoc false

    use Jido.Action,
      name: "record_prepared_emit",
      schema:
        Zoi.object(%{
          payload: Zoi.string(),
          input_signal_type: Zoi.string(),
          trusted_principal_id: Zoi.string(),
          saw_directive_dispatch?: Zoi.boolean(),
          saw_context_dispatch?: Zoi.boolean()
        })

    @impl true
    def run(params, context) do
      {:ok, %{},
       %StateOp.SetState{
         attrs: %{
           emitted_signal_type: context.signal.type,
           emitted_payload: params.payload,
           emitted_input_signal_type: params.input_signal_type,
           emitted_trusted_principal_id: params.trusted_principal_id,
           emitted_saw_directive_dispatch?: params.saw_directive_dispatch?,
           emitted_saw_context_dispatch?: params.saw_context_dispatch?
         }
       }}
    end
  end

  defmodule IdentityPlugin do
    @moduledoc false

    use Jido.Plugin,
      name: "identity",
      state_key: :identity,
      actions: [],
      signal_patterns: []

    @impl true
    def handle_signal(%Signal{type: "incoming.original"} = signal, _context) do
      rewritten = %{signal | type: "incoming.verified", data: %{payload: "verified"}}
      {:ok, {:continue, rewritten}}
    end

    def handle_signal(%Signal{type: "emit.start"} = signal, _context) do
      rewritten = %{signal | type: "emit.start.prepared"}
      {:ok, {:continue, rewritten}}
    end

    def handle_signal(signal, _context), do: {:ok, {:continue, signal}}

    @impl true
    def prepare_signal(%Signal{type: type} = signal, _context)
        when type in ["incoming.verified", "emit.start.prepared", "outbound.prepared"] do
      {:ok, signal, %{identity: %{principal_id: "agent_trusted"}}}
    end

    def prepare_signal(signal, _context), do: {:ok, signal, %{}}
  end

  defmodule AuthorizationPlugin do
    @moduledoc false

    use Jido.Plugin,
      name: "authorization",
      state_key: :authorization,
      actions: [],
      signal_patterns: []

    @impl true
    def prepare_signal(signal, %{trusted_context: %{identity: %{principal_id: principal_id}}}) do
      {:ok, signal, %{authorization: %{scope: "scope:#{principal_id}"}}}
    end

    def prepare_signal(signal, _context), do: {:ok, signal, %{}}

    @impl true
    def prepare_action(_signal, {RecordTrustedContextAction, _params}, %{
          trusted_context: %{identity: %{principal_id: "agent_trusted"}}
        }) do
      {:ok, %{action_authorized?: true}}
    end

    def prepare_action(_signal, {RecordTrustedContextAction, _params, _action_context}, %{
          trusted_context: %{identity: %{principal_id: "agent_trusted"}}
        }) do
      {:ok, %{action_authorized?: true}}
    end

    def prepare_action(_signal, {EmitRawSignalAction, _params}, %{
          trusted_context: %{identity: %{principal_id: "agent_trusted"}}
        }) do
      {:ok, %{emit_authorized?: true}}
    end

    def prepare_action(_signal, {RecordPreparedEmitAction, _params}, %{
          trusted_context: %{identity: %{principal_id: "agent_trusted"}}
        }) do
      {:ok, %{record_emit_authorized?: true}}
    end

    def prepare_action(_signal, _action_arg, _context), do: {:error, :unauthorized}
  end

  defmodule ReservedContextPlugin do
    @moduledoc false

    use Jido.Plugin,
      name: "reserved_context",
      state_key: :reserved_context,
      actions: [],
      signal_patterns: []

    @impl true
    def prepare_signal(signal, _context), do: {:ok, signal, %{state: :forbidden}}
  end

  defmodule DuplicateContextPluginA do
    @moduledoc false

    use Jido.Plugin,
      name: "duplicate_context_a",
      state_key: :duplicate_context_a,
      actions: [],
      signal_patterns: []

    @impl true
    def prepare_signal(signal, _context), do: {:ok, signal, %{identity: %{principal_id: "a"}}}
  end

  defmodule DuplicateContextPluginB do
    @moduledoc false

    use Jido.Plugin,
      name: "duplicate_context_b",
      state_key: :duplicate_context_b,
      actions: [],
      signal_patterns: []

    @impl true
    def prepare_signal(signal, _context), do: {:ok, signal, %{identity: %{principal_id: "b"}}}
  end

  defmodule RejectActionPlugin do
    @moduledoc false

    use Jido.Plugin,
      name: "reject_action",
      state_key: :reject_action,
      actions: [],
      signal_patterns: []

    @impl true
    def prepare_action(_signal, _action_arg, _context), do: {:error, :blocked_action}
  end

  defmodule ActionContextOverridePlugin do
    @moduledoc false

    use Jido.Plugin,
      name: "action_context_override",
      state_key: :action_context_override,
      actions: [],
      signal_patterns: []

    @impl true
    def handle_signal(%Signal{type: "incoming.context_override"} = signal, _context) do
      action = {
        RecordTrustedContextAction,
        %{payload: "from_action"},
        %{
          identity: %{principal_id: "action_supplied"},
          authorization: %{scope: "scope:action_supplied"}
        }
      }

      prepared_signal = %{signal | type: "incoming.verified", data: %{payload: "from_signal"}}

      {:ok, {:override, action, prepared_signal}}
    end

    def handle_signal(signal, _context), do: {:ok, {:continue, signal}}
  end

  defmodule RejectSignalPlugin do
    @moduledoc false

    use Jido.Plugin,
      name: "reject_signal",
      state_key: :reject_signal,
      actions: [],
      signal_patterns: []

    @impl true
    def prepare_signal(_signal, _context), do: {:error, :blocked_signal}
  end

  defmodule InvalidPrepareSignalPlugin do
    @moduledoc false

    use Jido.Plugin,
      name: "invalid_prepare_signal",
      state_key: :invalid_prepare_signal,
      actions: [],
      signal_patterns: []

    @impl true
    def prepare_signal(signal, _context), do: {:ok, signal, :not_a_map}
  end

  defmodule InvalidPrepareActionPlugin do
    @moduledoc false

    use Jido.Plugin,
      name: "invalid_prepare_action",
      state_key: :invalid_prepare_action,
      actions: [],
      signal_patterns: []

    @impl true
    def prepare_action(_signal, _action_arg, _context), do: {:ok, :not_a_map}
  end

  defmodule ReservedActionContextPlugin do
    @moduledoc false

    use Jido.Plugin,
      name: "reserved_action_context",
      state_key: :reserved_action_context,
      actions: [],
      signal_patterns: []

    @impl true
    def prepare_signal(signal, _context) do
      {:ok, signal, %{identity: %{principal_id: "agent_trusted"}}}
    end

    @impl true
    def prepare_action(_signal, _action_arg, _context), do: {:ok, %{state: :forbidden}}
  end

  defmodule DuplicateActionContextPlugin do
    @moduledoc false

    use Jido.Plugin,
      name: "duplicate_action_context",
      state_key: :duplicate_action_context,
      actions: [],
      signal_patterns: []

    @impl true
    def prepare_signal(signal, _context) do
      {:ok, signal, %{identity: %{principal_id: "agent_trusted"}}}
    end

    @impl true
    def prepare_action(_signal, _action_arg, _context) do
      {:ok, %{identity: %{principal_id: "action_phase"}}}
    end
  end

  defmodule CrashSignalPlugin do
    @moduledoc false

    use Jido.Plugin,
      name: "crash_signal",
      state_key: :crash_signal,
      actions: [],
      signal_patterns: []

    @impl true
    def prepare_signal(_signal, _context), do: raise("signal boom")
  end

  defmodule CrashActionPlugin do
    @moduledoc false

    use Jido.Plugin,
      name: "crash_action",
      state_key: :crash_action,
      actions: [],
      signal_patterns: []

    @impl true
    def prepare_action(_signal, _action_arg, _context), do: raise("action boom")
  end

  defmodule PrepareEmitPlugin do
    @moduledoc false

    use Jido.Plugin,
      name: "prepare_emit",
      state_key: :prepare_emit,
      actions: [],
      signal_patterns: ["no.outbound.matches"]

    @impl true
    def prepare_emit(%Signal{type: "outbound.raw"} = signal, context) do
      {:ok,
       %{
         signal
         | type: "outbound.prepared",
           data: %{
             payload: "prepared",
             input_signal_type: context.input_signal.type,
             trusted_principal_id: context.trusted_context.identity.principal_id,
             saw_directive_dispatch?: context.directive.dispatch == {:logger, level: :info},
             saw_context_dispatch?: context.dispatch == {:logger, level: :info}
           }
       }, nil}
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

  defmodule InvalidPrepareEmitPlugin do
    @moduledoc false

    use Jido.Plugin,
      name: "invalid_prepare_emit",
      state_key: :invalid_prepare_emit,
      actions: [],
      signal_patterns: []

    @impl true
    def prepare_emit(%Signal{type: "outbound.raw"}, _context), do: {:ok, :not_a_signal}
    def prepare_emit(signal, _context), do: {:ok, signal}
  end

  defmodule CrashEmitPlugin do
    @moduledoc false

    use Jido.Plugin,
      name: "crash_emit",
      state_key: :crash_emit,
      actions: [],
      signal_patterns: []

    @impl true
    def prepare_emit(%Signal{type: "outbound.raw"}, _context), do: raise("emit boom")
    def prepare_emit(signal, _context), do: {:ok, signal}
  end

  defmodule TrustedAgent do
    @moduledoc false

    use Jido.Agent,
      name: "trusted_agent",
      schema: [
        trusted_principal_id: [type: :string, default: nil],
        trusted_scope: [type: :string, default: nil],
        prepared_signal_type: [type: :string, default: nil],
        payload: [type: :string, default: nil],
        params_contain_principal?: [type: :boolean, default: nil]
      ],
      plugins: [IdentityPlugin, AuthorizationPlugin]

    def signal_routes(_ctx), do: [{"incoming.verified", RecordTrustedContextAction}]
  end

  defmodule ContextOverrideAgent do
    @moduledoc false

    use Jido.Agent,
      name: "context_override_agent",
      schema: [
        trusted_principal_id: [type: :string, default: nil],
        trusted_scope: [type: :string, default: nil],
        prepared_signal_type: [type: :string, default: nil],
        payload: [type: :string, default: nil],
        params_contain_principal?: [type: :boolean, default: nil]
      ],
      plugins: [ActionContextOverridePlugin, IdentityPlugin, AuthorizationPlugin]
  end

  defmodule ReservedContextAgent do
    @moduledoc false

    use Jido.Agent,
      name: "reserved_context_agent",
      plugins: [ReservedContextPlugin]

    def signal_routes(_ctx), do: [{"incoming.verified", RecordTrustedContextAction}]
  end

  defmodule DuplicateContextAgent do
    @moduledoc false

    use Jido.Agent,
      name: "duplicate_context_agent",
      plugins: [DuplicateContextPluginA, DuplicateContextPluginB]

    def signal_routes(_ctx), do: [{"incoming.verified", RecordTrustedContextAction}]
  end

  defmodule RejectActionAgent do
    @moduledoc false

    use Jido.Agent,
      name: "reject_action_agent",
      plugins: [RejectActionPlugin]

    def signal_routes(_ctx), do: [{"incoming.verified", RecordTrustedContextAction}]
  end

  defmodule RejectSignalAgent do
    @moduledoc false

    use Jido.Agent,
      name: "reject_signal_agent",
      plugins: [RejectSignalPlugin]

    def signal_routes(_ctx), do: [{"incoming.verified", RecordTrustedContextAction}]
  end

  defmodule InvalidPrepareSignalAgent do
    @moduledoc false

    use Jido.Agent,
      name: "invalid_prepare_signal_agent",
      plugins: [InvalidPrepareSignalPlugin]

    def signal_routes(_ctx), do: [{"incoming.verified", RecordTrustedContextAction}]
  end

  defmodule InvalidPrepareActionAgent do
    @moduledoc false

    use Jido.Agent,
      name: "invalid_prepare_action_agent",
      plugins: [InvalidPrepareActionPlugin]

    def signal_routes(_ctx), do: [{"incoming.verified", RecordTrustedContextAction}]
  end

  defmodule ReservedActionContextAgent do
    @moduledoc false

    use Jido.Agent,
      name: "reserved_action_context_agent",
      plugins: [ReservedActionContextPlugin]

    def signal_routes(_ctx), do: [{"incoming.verified", RecordTrustedContextAction}]
  end

  defmodule DuplicateActionContextAgent do
    @moduledoc false

    use Jido.Agent,
      name: "duplicate_action_context_agent",
      plugins: [DuplicateActionContextPlugin]

    def signal_routes(_ctx), do: [{"incoming.verified", RecordTrustedContextAction}]
  end

  defmodule CrashSignalAgent do
    @moduledoc false

    use Jido.Agent,
      name: "crash_signal_agent",
      plugins: [CrashSignalPlugin]

    def signal_routes(_ctx), do: [{"incoming.verified", RecordTrustedContextAction}]
  end

  defmodule CrashActionAgent do
    @moduledoc false

    use Jido.Agent,
      name: "crash_action_agent",
      plugins: [CrashActionPlugin]

    def signal_routes(_ctx), do: [{"incoming.verified", RecordTrustedContextAction}]
  end

  defmodule EmitAgent do
    @moduledoc false

    use Jido.Agent,
      name: "emit_agent",
      schema: [
        emitted_signal_type: [type: :string, default: nil],
        emitted_payload: [type: :string, default: nil],
        emitted_input_signal_type: [type: :string, default: nil],
        emitted_trusted_principal_id: [type: :string, default: nil],
        emitted_saw_directive_dispatch?: [type: :boolean, default: nil],
        emitted_saw_context_dispatch?: [type: :boolean, default: nil]
      ],
      plugins: [IdentityPlugin, AuthorizationPlugin, PrepareEmitPlugin]

    def signal_routes(_ctx) do
      [
        {"emit.start.prepared", EmitRawSignalAction},
        {"outbound.prepared", RecordPreparedEmitAction}
      ]
    end
  end

  defmodule RejectEmitAgent do
    @moduledoc false

    use Jido.Agent,
      name: "reject_emit_agent",
      plugins: [IdentityPlugin, AuthorizationPlugin, RejectEmitPlugin]

    def signal_routes(_ctx), do: [{"emit.start.prepared", EmitRawSignalAction}]
  end

  defmodule InvalidPrepareEmitAgent do
    @moduledoc false

    use Jido.Agent,
      name: "invalid_prepare_emit_agent",
      plugins: [IdentityPlugin, AuthorizationPlugin, InvalidPrepareEmitPlugin]

    def signal_routes(_ctx), do: [{"emit.start.prepared", EmitRawSignalAction}]
  end

  defmodule CrashEmitAgent do
    @moduledoc false

    use Jido.Agent,
      name: "crash_emit_agent",
      plugins: [IdentityPlugin, AuthorizationPlugin, CrashEmitPlugin]

    def signal_routes(_ctx), do: [{"emit.start.prepared", EmitRawSignalAction}]
  end

  describe "prepare_signal/2 and prepare_action/3" do
    test "prepare_signal receives rewritten signal and contributes trusted context", %{jido: jido} do
      {:ok, pid} = Jido.AgentServer.start_link(agent: TrustedAgent, jido: jido)

      signal = Signal.new!("incoming.original", %{payload: "original"}, source: "/test")
      {:ok, agent} = Jido.AgentServer.call(pid, signal)

      assert agent.state.trusted_principal_id == "agent_trusted"
      assert agent.state.trusted_scope == "scope:agent_trusted"
      assert agent.state.prepared_signal_type == "incoming.verified"
      assert agent.state.payload == "verified"
      assert agent.state.params_contain_principal? == false
    end

    test "trusted context wins over action-supplied context", %{jido: jido} do
      {:ok, pid} = Jido.AgentServer.start_link(agent: ContextOverrideAgent, jido: jido)

      signal = Signal.new!("incoming.context_override", %{}, source: "/test")
      {:ok, agent} = Jido.AgentServer.call(pid, signal)

      assert agent.state.trusted_principal_id == "agent_trusted"
      assert agent.state.trusted_scope == "scope:agent_trusted"
      assert agent.state.prepared_signal_type == "incoming.verified"
      assert agent.state.payload == "from_action"
      assert agent.state.params_contain_principal? == false
    end

    test "prepare_action rejects after route resolution", %{jido: jido} do
      {:ok, pid} = Jido.AgentServer.start_link(agent: RejectActionAgent, jido: jido)

      signal = Signal.new!("incoming.verified", %{payload: "x"}, source: "/test")
      assert {:error, error} = Jido.AgentServer.call(pid, signal)
      assert Exception.message(error) =~ "Plugin prepare_action failed"
    end

    test "prepare_signal errors fail closed through the configured error policy", %{jido: jido} do
      parent = self()

      error_policy = fn directive, state ->
        send(parent, {:phase_error, directive.context, directive.error})
        {:ok, state}
      end

      {:ok, pid} =
        Jido.AgentServer.start_link(
          agent: RejectSignalAgent,
          jido: jido,
          error_policy: error_policy
        )

      signal = Signal.new!("incoming.verified", %{payload: "x"}, source: "/test")
      assert {:error, error} = Jido.AgentServer.call(pid, signal)
      assert Exception.message(error) =~ "Plugin prepare_signal failed"
      assert_receive {:phase_error, :plugin_prepare_signal, policy_error}, 500
      assert Exception.message(policy_error) =~ "Plugin prepare_signal failed"
    end

    test "invalid prepare_signal results fail closed", %{jido: jido} do
      {:ok, pid} = Jido.AgentServer.start_link(agent: InvalidPrepareSignalAgent, jido: jido)

      signal = Signal.new!("incoming.verified", %{payload: "x"}, source: "/test")
      assert {:error, error} = Jido.AgentServer.call(pid, signal)
      assert Exception.message(error) =~ "Plugin prepare_signal returned invalid result"
    end

    test "invalid prepare_action results fail closed", %{jido: jido} do
      {:ok, pid} = Jido.AgentServer.start_link(agent: InvalidPrepareActionAgent, jido: jido)

      signal = Signal.new!("incoming.verified", %{payload: "x"}, source: "/test")
      assert {:error, error} = Jido.AgentServer.call(pid, signal)
      assert Exception.message(error) =~ "Plugin prepare_action returned invalid result"
    end

    test "prepare_signal crashes fail closed without stopping the server", %{jido: jido} do
      {:ok, pid} = Jido.AgentServer.start_link(agent: CrashSignalAgent, jido: jido)

      signal = Signal.new!("incoming.verified", %{payload: "x"}, source: "/test")
      assert {:error, error} = Jido.AgentServer.call(pid, signal)
      assert Exception.message(error) =~ "Plugin prepare_signal crashed"
      assert {:ok, _state} = Jido.AgentServer.state(pid)
    end

    test "prepare_action crashes fail closed without stopping the server", %{jido: jido} do
      {:ok, pid} = Jido.AgentServer.start_link(agent: CrashActionAgent, jido: jido)

      signal = Signal.new!("incoming.verified", %{payload: "x"}, source: "/test")
      assert {:error, error} = Jido.AgentServer.call(pid, signal)
      assert Exception.message(error) =~ "Plugin prepare_action crashed"
      assert {:ok, _state} = Jido.AgentServer.state(pid)
    end

    test "prepare_signal and prepare_action run on async signal path", %{jido: jido} do
      {:ok, pid} = Jido.AgentServer.start_link(agent: TrustedAgent, jido: jido)

      signal = Signal.new!("incoming.original", %{payload: "original"}, source: "/test")
      :ok = Jido.AgentServer.cast(pid, signal)

      state =
        eventually_state(pid, fn state ->
          state.agent.state.trusted_principal_id == "agent_trusted"
        end)

      assert state.agent.state.trusted_scope == "scope:agent_trusted"
      assert state.agent.state.prepared_signal_type == "incoming.verified"
    end

    test "reserved trusted context keys fail closed", %{jido: jido} do
      {:ok, pid} = Jido.AgentServer.start_link(agent: ReservedContextAgent, jido: jido)

      signal = Signal.new!("incoming.verified", %{payload: "x"}, source: "/test")
      assert {:error, error} = Jido.AgentServer.call(pid, signal)
      assert Exception.message(error) =~ "reserved trusted context keys"
    end

    test "duplicate trusted context keys fail closed", %{jido: jido} do
      {:ok, pid} = Jido.AgentServer.start_link(agent: DuplicateContextAgent, jido: jido)

      signal = Signal.new!("incoming.verified", %{payload: "x"}, source: "/test")
      assert {:error, error} = Jido.AgentServer.call(pid, signal)
      assert Exception.message(error) =~ "duplicate trusted context keys"
    end

    test "prepare_action reserved trusted context keys fail closed", %{jido: jido} do
      {:ok, pid} = Jido.AgentServer.start_link(agent: ReservedActionContextAgent, jido: jido)

      signal = Signal.new!("incoming.verified", %{payload: "x"}, source: "/test")
      assert {:error, error} = Jido.AgentServer.call(pid, signal)
      assert Exception.message(error) =~ "reserved trusted context keys"
    end

    test "prepare_action duplicate trusted context keys fail closed", %{jido: jido} do
      {:ok, pid} = Jido.AgentServer.start_link(agent: DuplicateActionContextAgent, jido: jido)

      signal = Signal.new!("incoming.verified", %{payload: "x"}, source: "/test")
      assert {:error, error} = Jido.AgentServer.call(pid, signal)
      assert Exception.message(error) =~ "duplicate trusted context keys"
    end
  end

  describe "prepare_emit/2" do
    test "call path passes prepared input signal and trusted context to prepare_emit", %{
      jido: jido
    } do
      {:ok, pid} = Jido.AgentServer.start_link(agent: EmitAgent, jido: jido)

      signal = Signal.new!("emit.start", %{}, source: "/test")
      {:ok, _agent} = Jido.AgentServer.call(pid, signal)

      state =
        eventually_state(pid, fn state ->
          state.agent.state.emitted_signal_type == "outbound.prepared"
        end)

      assert state.agent.state.emitted_payload == "prepared"
      assert state.agent.state.emitted_input_signal_type == "emit.start.prepared"
      assert state.agent.state.emitted_trusted_principal_id == "agent_trusted"
      assert state.agent.state.emitted_saw_directive_dispatch? == true
      assert state.agent.state.emitted_saw_context_dispatch? == true
      assert state.current_trusted_context == %{}
    end

    test "cast path passes prepared input signal and trusted context to prepare_emit", %{
      jido: jido
    } do
      {:ok, pid} = Jido.AgentServer.start_link(agent: EmitAgent, jido: jido)

      signal = Signal.new!("emit.start", %{}, source: "/test")
      :ok = Jido.AgentServer.cast(pid, signal)

      state =
        eventually_state(pid, fn state ->
          state.agent.state.emitted_signal_type == "outbound.prepared"
        end)

      assert state.agent.state.emitted_input_signal_type == "emit.start.prepared"
      assert state.agent.state.emitted_trusted_principal_id == "agent_trusted"
      assert state.current_trusted_context == %{}
    end

    test "prepare_emit errors fail closed through the configured error policy", %{jido: jido} do
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
    end

    test "invalid prepare_emit results fail closed through the configured error policy", %{
      jido: jido
    } do
      parent = self()

      error_policy = fn directive, state ->
        send(parent, {:prepare_emit_error, directive.context, directive.error})
        {:ok, state}
      end

      {:ok, pid} =
        Jido.AgentServer.start_link(
          agent: InvalidPrepareEmitAgent,
          jido: jido,
          error_policy: error_policy
        )

      signal = Signal.new!("emit.start", %{}, source: "/test")
      assert {:ok, _agent} = Jido.AgentServer.call(pid, signal)

      assert_receive {:prepare_emit_error, :plugin_prepare_emit, error}, 500
      assert Exception.message(error) =~ "Plugin prepare_emit returned invalid result"
      assert {:ok, state} = Jido.AgentServer.state(pid)
      assert state.current_trusted_context == %{}
    end

    test "prepare_emit crashes fail closed through the configured error policy", %{jido: jido} do
      parent = self()

      error_policy = fn directive, state ->
        send(parent, {:prepare_emit_error, directive.context, directive.error})
        {:ok, state}
      end

      {:ok, pid} =
        Jido.AgentServer.start_link(
          agent: CrashEmitAgent,
          jido: jido,
          error_policy: error_policy
        )

      signal = Signal.new!("emit.start", %{}, source: "/test")
      assert {:ok, _agent} = Jido.AgentServer.call(pid, signal)

      assert_receive {:prepare_emit_error, :plugin_prepare_emit, error}, 500
      assert Exception.message(error) =~ "Plugin prepare_emit crashed"
      assert {:ok, state} = Jido.AgentServer.state(pid)
      assert state.current_trusted_context == %{}
    end
  end
end

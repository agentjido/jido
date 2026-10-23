defmodule JidoTest.AgentServer.PluginRuntime.RulesTest do
  use JidoTest.Case, async: true
  use Covenant.Case, component: "jido.agent_server.plugin_runtime", async: true

  alias Jido.AgentServer.Plugin
  alias Jido.AgentServer.Plugin.{Callbacks, Commit}
  alias Jido.Plugin.{DirectiveContext, Init, SignalContext}

  defmodule Effect do
    use Jido.Agent.Directive
    defstruct [:label]
  end

  defmodule NoRuntime do
    use Jido.Plugin
    def after_commit(_, _, _), do: :ok
  end

  defmodule UnsafeRuntime do
    use Jido.Plugin
    def child_spec(_), do: %{id: __MODULE__, start: {Task, :start_link, [fn -> :ok end]}}
  end

  defmodule SafeRuntime do
    use Jido.Plugin
    def child_spec(_), do: %{id: __MODULE__, start: {Task, :start_link, [fn -> :ok end]}}
    def quiesce(_, _), do: :ok
    def resume(_, _), do: :ok
  end

  defmodule CallbackPlugin do
    use Jido.Plugin
    def state_spec(_), do: {:owned, Zoi.integer() |> Zoi.default(0)}
    def directives(_), do: [Effect]

    def child_spec(%Init{options: opts}) do
      case opts[:mode] do
        :temporary ->
          %{id: __MODULE__, start: {Task, :start_link, [fn -> :ok end]}, restart: :temporary}

        :invalid ->
          %{id: __MODULE__}

        :missing_start ->
          %{id: __MODULE__, start: {__MODULE__, :missing, []}}

        :raise ->
          raise "private child failure"

        :throw ->
          throw(:private_child_failure)

        _ ->
          %{id: __MODULE__, start: {Task, :start_link, [fn -> :ok end]}}
      end
    end

    def await_ready(_, opts), do: status(opts)
    def after_commit(_, _, opts), do: status(opts)
    def dispatch(_, _, _, opts), do: status(opts)

    def admit(_, _, opts) do
      case opts[:mode] do
        :error -> {:error, :denied}
        :invalid -> :invalid
        :raise -> raise "private callback failure"
        _ -> {:ok, :runtime_input}
      end
    end

    defp status(opts) do
      case opts[:mode] do
        :error -> {:error, :denied}
        :invalid -> :invalid
        :raise -> raise "private callback failure"
        _ -> :ok
      end
    end
  end

  defmodule FirstOutbound do
    use Jido.Plugin
    def state_spec(_), do: {:first, Zoi.atom() |> Zoi.default(:first)}

    def prepare_outbound(runtime, signal, context, opts) do
      send(self(), {:outbound, :first, runtime, context.plugin_state, opts[:marker]})
      {:ok, update_in(signal.data[:trace], &["first" | List.wrap(&1)])}
    end
  end

  defmodule SecondOutbound do
    use Jido.Plugin
    def state_spec(_), do: {:second, Zoi.atom() |> Zoi.default(:second)}

    def prepare_outbound(runtime, signal, context, opts) do
      send(self(), {:outbound, :second, runtime, context.plugin_state, opts[:marker]})

      case opts[:mode] do
        :error -> {:error, :blocked}
        :invalid -> :invalid
        :invalid_signal -> {:ok, %{signal | source: "not a URI reference"}}
        :raise -> raise "private outbound failure"
        _ -> {:ok, update_in(signal.data[:trace], &["second" | List.wrap(&1)])}
      end
    end
  end

  @tag obligation: [
         "jido.agent_server.plugin_runtime.I1",
         "jido.agent_server.plugin_runtime.I9",
         "jido.agent_server.plugin_runtime.I12"
       ]
  test "runtime selection rejects unsafe changes and selects only a dispatch owner" do
    assert {:ok, [safe, unsafe, rootless]} =
             Jido.Plugin.Normalizer.normalize_all([SafeRuntime, UnsafeRuntime, NoRuntime])

    assert :ok = Plugin.validate_changes([rootless], [NoRuntime])
    assert :ok = Plugin.validate_changes([safe], [SafeRuntime])

    assert {:error, error} = Plugin.validate_changes([unsafe], [UnsafeRuntime])
    assert error.code == :plugin_quiescence_required
    assert error.path == [:extensions]
    assert error.details.plugin == UnsafeRuntime

    assert Plugin.directive_owner([rootless], %Effect{}) == nil
    assert {:ok, [owner]} = Jido.Plugin.Normalizer.normalize_all([CallbackPlugin])
    assert Plugin.directive_owner([owner], %Effect{}) == owner
    assert Plugin.directive_owner([%{owner | agent_server: nil}], %Effect{}) == nil
    assert Plugin.directive_owner([put_in(owner.agent_server.dispatch?, false)], %Effect{}) == nil
  end

  @tag obligation: "jido.agent_server.plugin_runtime.I8"
  test "outbound callbacks run in reverse order with their own state, root, and options" do
    signal = Jido.Signal.new!("plugin.output", %{trace: []}, source: "/test")

    context =
      struct!(SignalContext,
        turn_id: "turn",
        agent_id: "agent",
        source_signal: signal,
        effective_signal: signal,
        target: self(),
        state_version: 3,
        plugin_state: nil
      )

    assert {:ok, specs} =
             Jido.Plugin.Normalizer.normalize_all([
               {FirstOutbound, marker: :first_option},
               {SecondOutbound, marker: :second_option}
             ])

    refs = %{FirstOutbound => :first_root, SecondOutbound => :second_root}
    state = %{first: :first_state, second: :second_state}

    assert {:ok, prepared} = Callbacks.prepare_outbound(signal, specs, refs, context, state)
    assert prepared.data.trace == ["first", "second"]

    assert_receive {:outbound, :second, :second_root, :second_state, :second_option}
    assert_receive {:outbound, :first, :first_root, :first_state, :first_option}

    assert {:ok, [rootless]} = Jido.Plugin.Normalizer.normalize_all([NoRuntime])
    assert Callbacks.prepare_outbound(signal, [rootless], %{}, context, %{}) == {:ok, signal}
  end

  @tag obligation: "jido.agent_server.plugin_runtime.I8"
  test "outbound preparation preserves explicit errors and rejects callback faults" do
    signal = Jido.Signal.new!("plugin.output", %{}, source: "/test")

    context =
      struct!(SignalContext,
        turn_id: "turn",
        agent_id: "agent",
        source_signal: signal,
        effective_signal: signal,
        target: self(),
        state_version: 1,
        plugin_state: nil
      )

    for {mode, expected} <- [error: :blocked, invalid: :plugin_invalid_callback_result] do
      assert {:ok, [spec]} =
               Jido.Plugin.Normalizer.normalize_all([{SecondOutbound, mode: mode}])

      assert {:error, error} = Callbacks.prepare_outbound(signal, [spec], %{}, context, %{})
      assert error == expected or error.details.code == expected

      if mode == :invalid,
        do: assert(error.details.result == :invalid)
    end

    assert {:ok, [spec]} =
             Jido.Plugin.Normalizer.normalize_all([{SecondOutbound, mode: :invalid_signal}])

    assert {:error, invalid_signal} =
             Callbacks.prepare_outbound(signal, [spec], %{}, context, %{})

    assert invalid_signal.details.plugin == SecondOutbound
    assert [_ | _] = invalid_signal.details.errors

    assert {:ok, [spec]} = Jido.Plugin.Normalizer.normalize_all([{SecondOutbound, mode: :raise}])
    assert {:error, raised} = Callbacks.prepare_outbound(signal, [spec], %{}, context, %{})
    assert raised.details.code == :plugin_callback_failed
    assert raised.details.callback == :prepare_outbound
  end

  @tag obligation: "jido.agent_server.plugin_runtime.I1"
  test "child specifications accept one permanent root and retain structured failures" do
    init = %Init{agent_server: self(), agent_id: "agent", module: CallbackPlugin}
    assert {:ok, [rootless]} = Jido.Plugin.Normalizer.normalize_all([NoRuntime])
    assert Callbacks.child_spec(init, rootless) == :none

    assert {:ok, [valid]} = Jido.Plugin.Normalizer.normalize_all([CallbackPlugin])
    assert {:ok, child_spec} = Callbacks.child_spec(init, valid)
    assert child_spec.id == CallbackPlugin
    assert Map.get(child_spec, :restart, :permanent) == :permanent

    for {mode, detail} <- [temporary: :restart, invalid: :child_spec, missing_start: :reason] do
      assert {:ok, [spec]} = Jido.Plugin.Normalizer.normalize_all([{CallbackPlugin, mode: mode}])
      assert {:error, error} = Callbacks.child_spec(init, spec)
      assert error.details.plugin == CallbackPlugin
      assert error.details.facet == CallbackPlugin
      assert Map.has_key?(error.details, detail)
    end

    for {mode, detail} <- [raise: :error, throw: :reason] do
      assert {:ok, [spec]} = Jido.Plugin.Normalizer.normalize_all([{CallbackPlugin, mode: mode}])
      assert {:error, error} = Callbacks.child_spec(init, spec)
      assert error.details.plugin == CallbackPlugin
      assert error.details.facet == CallbackPlugin
      assert Map.has_key?(error.details, detail)

      if mode == :throw,
        do: assert(error.details.kind == :throw)
    end
  end

  @tag obligation: [
         "jido.agent_server.plugin_runtime.I4",
         "jido.agent_server.plugin_runtime.I6",
         "jido.agent_server.plugin_runtime.I9"
       ]
  test "callback adapters preserve explicit errors and report invalid or raised results" do
    agent =
      Jido.Agent.define!(%{name: "plugin_callback_rules"})
      |> Jido.Agent.instantiate!(id: "plugin-callback-rules")

    signal = Jido.Signal.new!("plugin.callback", %{}, source: "/test")
    assert {:ok, command} = Jido.Agent.Command.new(agent, signal)

    commit = %Commit{
      plugin: CallbackPlugin,
      turn_id: "turn",
      agent_id: agent.id,
      agent_module: agent.module,
      plugin_state: nil,
      state_version: 1
    }

    directive_context =
      struct!(DirectiveContext,
        turn_id: "turn",
        agent_id: agent.id,
        source_signal: signal,
        effective_signal: signal,
        state_version: 1,
        plugin_state: nil
      )

    for mode <- [:invalid, :raise] do
      assert {:ok, [spec]} = Jido.Plugin.Normalizer.normalize_all([{CallbackPlugin, mode: mode}])

      assert {:error, admission} = Callbacks.admit(command, [spec], %{}, 0)
      assert admission.details.plugin == CallbackPlugin

      assert {:error, notification} = Callbacks.after_commit(spec, nil, commit)
      assert notification.details.plugin == CallbackPlugin

      assert {:error, dispatch} = Callbacks.dispatch(spec, nil, %Effect{}, directive_context)
      assert dispatch.details.plugin == CallbackPlugin

      assert {:error, readiness} = Callbacks.await_ready(spec, nil)
      assert readiness.details.plugin == CallbackPlugin

      expected =
        if mode == :invalid, do: :plugin_invalid_callback_result, else: :plugin_callback_failed

      for error <- [admission, notification, dispatch, readiness] do
        assert error.details.code == expected

        if mode == :invalid,
          do: assert(error.details.result == :invalid)
      end
    end

    assert {:ok, [spec]} = Jido.Plugin.Normalizer.normalize_all([{CallbackPlugin, mode: :error}])
    assert Callbacks.admit(command, [spec], %{}, 0) == {:error, :denied}
    assert Callbacks.after_commit(spec, nil, commit) == {:error, :denied}
    assert Callbacks.dispatch(spec, nil, %Effect{}, directive_context) == {:error, :denied}
    assert Callbacks.await_ready(spec, nil) == {:error, :denied}
  end
end

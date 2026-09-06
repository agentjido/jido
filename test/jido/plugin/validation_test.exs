defmodule Jido.Plugin.ValidationTest do
  use JidoTest.Case, async: true

  alias Jido.Plugin
  alias Jido.Plugin.{Init, SignalContext}

  defmodule Effect do
    defstruct [:value]
  end

  defmodule Empty do
    use Jido.Plugin
  end

  defmodule Configurable do
    use Jido.Plugin
    def state_spec(opts), do: Keyword.get(opts, :state, {:owned, Zoi.integer()})
    def directives(opts), do: Keyword.get(opts, :directives, [Effect])
    def validate_directive(effect, opts), do: Keyword.get(opts, :validation_result, {:ok, effect})
    def update_state(_current, _directives, opts), do: Keyword.fetch!(opts, :result)
    def dispatch(_, _, _, _), do: :ok

    def prepare_dispatch(_, signal, _, opts),
      do: Keyword.get(opts, :dispatch_result, {:ok, signal})
  end

  defmodule NoState do
    use Jido.Plugin
    def update_state(state, _, _), do: {:ok, state}
  end

  defmodule ThrowingChild do
    use Jido.Plugin
    def child_spec(_), do: throw(:bad_child_spec)
  end

  test "invalid Plugin declarations fail with a specific contract error" do
    for {declaration, fragment} <- [
          {Empty, "defines no capability"},
          {{Configurable, [:invalid]}, "options must be a keyword list"},
          {42, "Invalid Agent Plugin declaration"},
          {JidoTest.MissingPlugin, "could not be loaded"},
          {{Configurable, state: :invalid}, "state_spec/1 returned an invalid value"},
          {{Configurable, state: {:owned, Zoi.any() |> Zoi.refine(fn _ -> :ok end)}},
           "state schema must contain static data"},
          {{Configurable, directives: :invalid}, "directives/1 must return a list"},
          {{Configurable, directives: [42]}, "Directive modules must be atoms"},
          {{Configurable, directives: [Effect, Effect]}, "Directive modules must be unique"},
          {{Configurable, directives: []}, "dispatch/4 requires declared Directives"},
          {NoState, "update_state/3 requires state_spec/1"}
        ] do
      assert {:error, error} = Plugin.normalize_all([declaration])
      assert error.message =~ fragment
    end

    assert {:error, error} = Plugin.compose_schema(Zoi.integer(), [])
    assert error.message =~ "domain schema must be a field-based Zoi object"
  end

  test "invalid Plugin state and callback results do not return a candidate state" do
    for {result, message} <- [
          {{:ok, "invalid"}, "Agent Plugin state is invalid"},
          {:invalid, "Agent Plugin update_state/3 returned an invalid result"}
        ] do
      {:ok, specs} = Plugin.normalize_all([{Configurable, result: result}])
      assert {:error, error} = Plugin.update_state({:ok, %{owned: 1}, [%Effect{value: 2}]}, specs)
      assert error.message == message
    end

    {:ok, specs} = Plugin.normalize_all([{Configurable, result: {:ok, 2}}])

    assert {:ok, %{owned: 2}, [:unknown]} =
             Plugin.update_state({:ok, %{owned: 1}, [:unknown]}, specs)

    assert Plugin.directive_owner(specs, :unknown) == nil
    assert {:error, :failed} = Plugin.update_state({:error, :failed}, specs)
    assert {:error, :failed} = Plugin.protect_state({:error, :failed}, %{owned: 1}, specs)
    {:ok, [spec]} = Plugin.normalize_all([{Configurable, validation_result: :invalid}])
    assert {:error, error} = Plugin.validate_directive(spec, %Effect{})
    assert error.message == "Agent Plugin validate_directive/2 returned an invalid result"
  end

  test "outbound preparation rejects invalid results and preserves explicit errors" do
    outbound = signal("plugin.output")

    context = %SignalContext{
      turn_id: "turn",
      agent_id: "agent",
      source_signal: outbound,
      effective_signal: outbound,
      target: {:noop, []},
      state_version: 1,
      plugin_state: nil
    }

    for result <- [{:error, :blocked}, :invalid] do
      {:ok, specs} = Plugin.normalize_all([{Configurable, dispatch_result: result}])
      assert {:error, error} = Plugin.prepare_dispatch(outbound, specs, %{}, context, %{owned: 1})

      if result == :invalid,
        do: assert(error.message == "Agent Plugin prepare_dispatch/4 returned an invalid result"),
        else: assert(error == :blocked)
    end
  end

  test "child spec throws and unavailable owners return errors" do
    pid = spawn(fn -> :ok end)
    ref = Process.monitor(pid)
    assert_receive {:DOWN, ^ref, :process, ^pid, _}
    init = %Init{agent_server: pid, agent_id: "agent", module: ThrowingChild}
    assert {:error, {:agent_server_unavailable, _}} = Plugin.state(init)
    assert {:error, error} = Plugin.child_specs(init, [ThrowingChild])
    assert error.message == "Agent Plugin child_spec/1 failed"
    assert error.details.kind == :throw
    assert error.details.reason == :bad_child_spec
  end
end

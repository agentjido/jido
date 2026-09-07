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

  defmodule OptionValidator do
    use Jido.Plugin

    def validate_options(opts) do
      send(self(), {:callback, :validate_options, opts})

      case Keyword.fetch!(opts, :validation_result) do
        :raise -> raise ArgumentError, "Invalid Plugin options"
        :throw -> throw(:invalid_plugin_options)
        :exit -> exit(:invalid_plugin_options)
        result -> result
      end
    end

    def state_spec(opts) do
      send(self(), {:callback, :state_spec, opts})
      :none
    end

    def directives(opts) do
      send(self(), {:callback, :directives, opts})
      []
    end
  end

  defmodule FailingDirectives do
    use Jido.Plugin

    def directives(opts) do
      case Keyword.fetch!(opts, :failure) do
        :raise -> raise ArgumentError, "Invalid Directive setting"
        :throw -> throw(:invalid_directive_setting)
        :exit -> exit(:invalid_directive_setting)
        {:returned, error} -> {:error, error}
      end
    end
  end

  defmodule FailingStateSpec do
    use Jido.Plugin

    def state_spec(opts) do
      case Keyword.fetch!(opts, :failure) do
        :raise -> raise ArgumentError, "Invalid Plugin setting"
        :throw -> throw(:invalid_plugin_setting)
        :exit -> exit(:invalid_plugin_setting)
        :returned -> {:error, Jido.Error.validation_error("Invalid Plugin setting")}
      end
    end
  end

  test "state schema callback exceptions return structured errors before composition" do
    for failure <- [:raise, :throw, :exit] do
      assert {:error, error} =
               Jido.Agent.new(%{
                 name: "bad_plugin_state_schema",
                 schema: Zoi.object(%{}),
                 plugins: [{FailingStateSpec, failure: failure}]
               })

      assert error.message == "Agent Plugin state_spec/1 failed"
      assert error.details.plugin == FailingStateSpec
    end
  end

  test "state schema callback error structs are not treated as schema values" do
    assert {:error, error} =
             Jido.Agent.new(%{
               name: "returned_plugin_state_error",
               schema: Zoi.object(%{}),
               plugins: [{FailingStateSpec, failure: :returned}]
             })

    assert error.message == "Invalid Plugin setting"
  end

  test "a Plugin can use error as its state key" do
    assert {:ok, definition} =
             Jido.Agent.new(%{
               name: "error_field_plugin",
               schema: Zoi.object(%{}),
               plugins: [{Configurable, state: {:error, Zoi.integer() |> Zoi.default(7)}}]
             })

    assert {:ok, agent} = Jido.Agent.instantiate(definition)
    assert agent.state.error == 7
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

  test "state_spec requires a usable Zoi schema and a safe state key" do
    for {state_spec, message} <- [
          {{nil, Zoi.integer()}, "state key must not be nil"},
          {{:__struct__, Zoi.integer()}, "state key is reserved"},
          {{:owned, %URI{scheme: "https"}}, "state schema must be a Zoi schema"}
        ] do
      assert {:error, %Jido.Error.ValidationError{} = error} =
               Plugin.normalize_all([{Configurable, state: state_spec}])

      assert error.message == "Agent Plugin #{message}"
      assert error.details.plugin == Configurable
    end

    assert {:error, %Jido.Error.ValidationError{} = error} =
             Jido.Agent.new(%{
               name: "invalid_plugin_schema",
               schema: Zoi.object(%{}),
               plugins: [{Configurable, state: {:owned, %URI{scheme: "https"}}}]
             })

    assert error.message == "Agent Plugin state schema must be a Zoi schema"
  end

  test "normalizes options and declaration callbacks once for reusable specs" do
    original_opts = [validation_result: {:ok, [validated: true]}]

    assert {:ok, [spec]} = Plugin.normalize_all([{OptionValidator, original_opts}])
    assert spec.options == [validated: true]
    assert_received {:callback, :validate_options, ^original_opts}
    assert_received {:callback, :state_spec, [validated: true]}
    assert_received {:callback, :directives, [validated: true]}
    refute_received {:callback, _, _}

    assert {:ok, [^spec]} = Plugin.normalize_all([spec])
    refute_received {:callback, _, _}

    init = %Init{agent_server: self(), agent_id: "agent", module: OptionValidator}

    assert {:ok, _schema} = Plugin.compose_schema(Zoi.object(%{}), [spec])
    assert {:ok, [{OptionValidator, [validated: true]}]} = Plugin.canonical_declarations([spec])
    assert {:ok, []} = Plugin.child_specs(init, [spec])
    refute_received {:callback, _, _}
  end

  test "rejects mixed declarations and normalized specs before callbacks run" do
    original_opts = [validation_result: {:ok, [validated: true]}]
    declaration = {OptionValidator, original_opts}

    assert {:ok, [spec]} = Plugin.normalize_all([declaration])
    assert_received {:callback, :validate_options, ^original_opts}
    assert_received {:callback, :state_spec, [validated: true]}
    assert_received {:callback, :directives, [validated: true]}
    refute_received {:callback, _, _}

    assert {:error, first_error} = Plugin.normalize_all([declaration, spec])
    assert {:error, second_error} = Plugin.normalize_all([spec, declaration])

    assert first_error.message ==
             "Agent Plugin declarations cannot mix normalized specs and declarations"

    assert first_error.details == %{normalized_specs: [spec], declarations: [declaration]}
    assert second_error.message == first_error.message
    assert second_error.details == first_error.details
    assert second_error.kind == first_error.kind
    assert second_error.class == first_error.class
    refute_received {:callback, _, _}
  end

  test "option validation preserves errors and rejects invalid callback results" do
    expected = Jido.Error.validation_error("Invalid Plugin options")

    assert {:error, ^expected} =
             Plugin.normalize_all([
               {OptionValidator, validation_result: {:error, expected}}
             ])

    assert {:error, error} =
             Plugin.normalize_all([{OptionValidator, validation_result: :invalid}])

    assert error.message == "Agent Plugin validate_options/1 returned an invalid result"
    assert error.details.plugin == OptionValidator

    for invalid_options <- [[:not_keyword], :not_a_list] do
      assert {:error, error} =
               Plugin.normalize_all([
                 {OptionValidator, validation_result: {:ok, invalid_options}}
               ])

      assert error.message == "Agent Plugin validate_options/1 returned invalid options"
      assert error.details.plugin == OptionValidator
      assert error.details.options == invalid_options
    end

    assert {:error, :invalid_plugin_options} =
             Plugin.normalize_all([
               {OptionValidator, validation_result: {:error, :invalid_plugin_options}}
             ])
  end

  test "option validation exceptions become Plugin-scoped structured errors" do
    for {failure, kind} <- [raise: :error, throw: :throw, exit: :exit] do
      assert {:error, %Jido.Error.ExecutionError{} = error} =
               Plugin.normalize_all([{OptionValidator, validation_result: failure}])

      assert error.message == "Agent Plugin validate_options/1 failed"
      assert error.details.plugin == OptionValidator

      if kind == :error do
        assert %ArgumentError{message: "Invalid Plugin options"} = error.details.error
      else
        assert error.details.kind == kind
        assert error.details.reason == :invalid_plugin_options
      end
    end
  end

  test "directives callback failures keep their original structured error" do
    for {failure, kind} <- [raise: :error, throw: :throw, exit: :exit] do
      assert {:error, %Jido.Error.ExecutionError{} = error} =
               Plugin.normalize_all([{FailingDirectives, failure: failure}])

      assert error.message == "Agent Plugin directives/1 failed"
      assert error.details.plugin == FailingDirectives

      if kind == :error do
        assert %ArgumentError{message: "Invalid Directive setting"} = error.details.error
      else
        assert error.details.kind == kind
        assert error.details.reason == :invalid_directive_setting
      end
    end

    expected = Jido.Error.validation_error("Invalid Directive setting")

    assert {:error, ^expected} =
             Plugin.normalize_all([
               {FailingDirectives, failure: {:returned, expected}}
             ])

    assert {:error, :invalid_directive_setting} =
             Plugin.normalize_all([
               {FailingDirectives, failure: {:returned, :invalid_directive_setting}}
             ])
  end

  test "Directive owners must be loaded struct modules" do
    for {directive, message} <- [
          {JidoTest.MissingDirective, "must be loaded"},
          {String, "must define a struct"}
        ] do
      assert {:error, error} =
               Plugin.normalize_all([{Configurable, directives: [directive]}])

      assert error.message == "Agent Plugin Directive modules #{message}"
      assert error.details.plugin == Configurable
      assert error.details.directive == directive
    end
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

  test "outbound preparation validates the complete Signal after a transform" do
    outbound = signal("plugin.output")
    invalid = %{outbound | source: "not a URI reference"}

    context = %SignalContext{
      turn_id: "turn",
      agent_id: "agent",
      source_signal: outbound,
      effective_signal: outbound,
      target: {:noop, []},
      state_version: 1,
      plugin_state: nil
    }

    {:ok, specs} =
      Plugin.normalize_all([{Configurable, dispatch_result: {:ok, invalid}}])

    assert {:error, %Jido.Error.ExecutionError{} = error} =
             Plugin.prepare_dispatch(outbound, specs, %{}, context, %{owned: 1})

    assert error.message == "Agent Plugin prepare_dispatch/4 returned an invalid Signal"
    assert error.details.plugin == Configurable
    assert [_error | _rest] = error.details.errors
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

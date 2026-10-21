defmodule JidoTest.PluginContract.NormalizerTest do
  use Covenant.Case, component: "jido.plugin", async: true

  alias Jido.Plugin
  alias Jido.Plugin.Normalizer

  defmodule Effect do
    use Jido.Agent.Directive
    defstruct [:value]

    @impl true
    def validate(%__MODULE__{} = directive), do: {:ok, directive}
  end

  defmodule PlainStruct do
    defstruct [:value]
  end

  defmodule ValidatorWithoutStruct do
    def validate(value), do: {:ok, value}
  end

  defmodule Configurable do
    use Jido.Plugin,
      id: "contract.configurable",
      vsn: 4,
      option_keys: [
        agent: [:state_spec, :directives],
        agent_server: [:validation]
      ]

    @impl true
    def state_spec(opts) do
      send(self(), {:callback, :state_spec, opts})
      Keyword.get(opts, :state_spec, {:owned, Zoi.integer() |> Zoi.default(0)})
    end

    @impl true
    def directives(opts) do
      send(self(), {:callback, :directives, opts})
      Keyword.get(opts, :directives, [Effect])
    end

    @impl true
    def reduce(reduction, _opts), do: {:ok, reduction.plugin_state}

    @impl true
    def validate_options(opts) do
      send(self(), {:callback, :validate_options, opts})

      case Keyword.get(opts, :validation, :ok) do
        :raise -> raise ArgumentError, "bad Plugin options"
        :throw -> throw(:bad_plugin_options)
        :exit -> exit(:bad_plugin_options)
        result -> result
      end
    end

    @impl true
    def admit(_runtime, _admission, _opts), do: {:ok, nil}
  end

  defmodule OtherOwner do
    use Jido.Plugin
    def state_spec(_opts), do: {:other, Zoi.integer() |> Zoi.default(0)}
    def directives(_opts), do: [Effect]
    def reduce(reduction, _opts), do: {:ok, reduction.plugin_state}
  end

  defmodule SameStateOwner do
    use Jido.Plugin
    def state_spec(_opts), do: {:owned, Zoi.integer() |> Zoi.default(0)}
  end

  defmodule DistinctStateOwner do
    use Jido.Plugin
    def state_spec(_opts), do: {:distinct, Zoi.integer() |> Zoi.default(0)}
  end

  defmodule Full do
    use Jido.Plugin,
      vsn: 3,
      option_keys: [
        agent: [:agent_option],
        agent_server: [:server_option],
        persistence: [:persistence_option]
      ]

    def prepare(_preparation, opts), do: {:ok, opts}
    def state_spec(_opts), do: {:full_owned, Zoi.integer() |> Zoi.default(0)}
    def directives(_opts), do: [Effect]
    def reduce(reduction, _opts), do: {:ok, reduction.plugin_state}
    def validate_options(_opts), do: :ok
    def admit(_runtime, _admission, opts), do: {:ok, opts}
    def prepare_dispatch(_runtime, signal, _context, _opts), do: {:ok, signal}
    def dispatch(_runtime, _directive, _context, _opts), do: :ok
    def child_spec(_init), do: %{id: __MODULE__, start: {Task, :start_link, [fn -> :ok end]}}
    def await_ready(_runtime, _opts), do: :ok
    def quiesce(_runtime, _opts), do: :ok
    def resume(_runtime, _opts), do: :ok
    def after_commit(_runtime, _commit, _opts), do: :ok
    def dump(value, _context, _opts), do: {:ok, value}
    def load(value, _context, _opts), do: {:ok, value}
  end

  defmodule DumpOnly do
    use Jido.Plugin
    def state_spec(_opts), do: {:dumped, Zoi.integer()}
    def dump(value, _context, _opts), do: {:ok, value}
  end

  defmodule LoadOnly do
    use Jido.Plugin
    def state_spec(_opts), do: {:loaded, Zoi.integer()}
    def load(value, _context, _opts), do: {:ok, value}
  end

  defmodule QuiesceOnly do
    use Jido.Plugin
    def quiesce(_runtime, _opts), do: :ok
  end

  defmodule ResumeOnly do
    use Jido.Plugin
    def resume(_runtime, _opts), do: :ok
  end

  defmodule UnownedDispatch do
    use Jido.Plugin
    def dispatch(_runtime, _directive, _context, _opts), do: :ok
  end

  defmodule UnhandledDirective do
    use Jido.Plugin
    def directives(_opts), do: [Effect]
  end

  defmodule LegacyDirectiveValidation do
    use Jido.Plugin
    def state_spec(_opts), do: {:legacy_directive, Zoi.integer()}
    def directives(_opts), do: [Effect]
    def reduce(reduction, _opts), do: {:ok, reduction.plugin_state}
    def validate_directive(directive, _opts), do: {:ok, directive}
  end

  defmodule LegacyStateUpdate do
    use Jido.Plugin
    def state_spec(_opts), do: {:legacy_state, Zoi.integer()}
    def reduce(reduction, _opts), do: {:ok, reduction.plugin_state}
    def update_state(state, _directive, _opts), do: {:ok, state}
  end

  defmodule DynamicSchema do
    use Jido.Plugin
    def state_spec(_opts), do: {:dynamic, Zoi.any() |> Zoi.default(self())}
  end

  defmodule StateResult do
    use Jido.Plugin
    def state_spec(opts), do: Keyword.fetch!(opts, :result)
  end

  defmodule ServerOnly do
    use Jido.Plugin
    def admit(_runtime, _admission, _opts), do: {:ok, nil}
  end

  @tag obligation: ["jido.plugin.I1", "jido.plugin.I2"]
  test "one declaration exposes stable identity and exact callback owners" do
    assert Configurable.id() == "contract.configurable"
    assert Configurable.vsn() == 4
    assert {:ok, [%{manifest: manifest}]} = Normalizer.normalize_all([Configurable])
    assert manifest.module == Configurable
    assert manifest.vsn == 4
    assert manifest.agent == Configurable
    assert manifest.agent_server == Configurable
    assert manifest.persistence == nil

    assert Plugin.owner_callbacks() == [
             agent: [prepare: 2, state_spec: 1, directives: 1, reduce: 2],
             agent_server: [
               validate_options: 1,
               admit: 3,
               prepare_dispatch: 4,
               dispatch: 4,
               child_spec: 1,
               await_ready: 2,
               quiesce: 2,
               resume: 2,
               after_commit: 3
             ],
             persistence: [dump: 3, load: 3]
           ]
  end

  @tag obligation: "jido.plugin.I4"
  test "declarations normalize once and retain order and exact options" do
    options = [state_spec: {:owned, Zoi.integer()}, directives: [], validation: :ok]
    declaration = {Configurable, options}

    assert {:ok, [spec]} = Normalizer.normalize_all([declaration])
    assert spec.module == Configurable
    assert spec.options == options
    assert spec.agent.options == Keyword.take(options, [:state_spec, :directives])
    assert spec.agent_server.options == [validation: :ok]

    assert_received {:callback, :state_spec, agent_options}
    assert agent_options == spec.agent.options
    assert_received {:callback, :directives, ^agent_options}
    assert_received {:callback, :validate_options, [validation: :ok]}
    refute_received {:callback, _, _}

    assert {:ok, [^spec]} = Normalizer.normalize_all([spec])
    assert {:ok, [{Configurable, ^options}]} = Normalizer.canonical_declarations([spec])
    assert {:ok, [{Configurable, ^options}]} = Normalizer.declarations([spec])
    refute_received {:callback, _, _}

    assert {:ok, [first, second]} =
             Normalizer.normalize_all([
               declaration,
               {DistinctStateOwner, []}
             ])

    assert [first.module, second.module] == [Configurable, DistinctStateOwner]
  end

  @tag obligation: "jido.plugin.I4"
  test "normalization rejects malformed, mixed, repeated, and unloaded declarations" do
    assert {:ok, [spec]} = Normalizer.normalize_all([{Configurable, validation: :ok}])

    assert {:error, %{details: %{plugins: :not_a_list}}} =
             Normalizer.normalize_all(:not_a_list)

    assert {:error, %{details: %{plugins: :not_a_list}}} =
             Normalizer.declarations(:not_a_list)

    assert {:error, %{details: %{plugin: 42}}} = Normalizer.normalize_all([42])

    assert {:error, %{details: %{plugin: Configurable, options: [:invalid]}}} =
             Normalizer.normalize_all([{Configurable, [:invalid]}])

    assert {:error, %{details: %{plugin: JidoTest.MissingGenericPlugin, reason: :nofile}}} =
             Normalizer.normalize_all([JidoTest.MissingGenericPlugin])

    assert {:error, %{details: %{plugin: Configurable, declarations: [_, _]}}} =
             Normalizer.normalize_all([Configurable, Configurable])

    assert {:error, %{details: %{normalized_specs: [^spec], declarations: [Configurable]}}} =
             Normalizer.normalize_all([spec, Configurable])

    assert {:error, %{details: %{normalized_specs: [^spec], declarations: [Configurable]}}} =
             Normalizer.declarations([spec, Configurable])

    assert {:ok, [{Configurable, [validation: :ok]}]} = Normalizer.declarations([spec])

    assert {:ok, [{Configurable, []}]} = Normalizer.declarations([Configurable])

    assert {:error, %{details: %{plugin: {"not-a-module", []}}}} =
             Normalizer.normalize_all([{"not-a-module", []}])
  end

  @tag obligation: ["jido.plugin.I2", "jido.plugin.I3", "jido.plugin.I6"]
  test "a complete declaration produces narrow owner Specs" do
    options = [agent_option: :agent, server_option: :server, persistence_option: :store]
    assert {:ok, [spec]} = Normalizer.normalize_all([{Full, options}])

    assert spec.manifest.vsn == 3
    assert spec.agent.package == Full
    assert spec.agent.module == Full
    assert spec.agent.options == [agent_option: :agent]
    assert spec.agent.state_key == :full_owned
    assert %Zoi.Types.Integer{} = spec.agent.state_schema
    assert spec.agent.directive_modules == [Effect]

    assert spec.agent_server.package == Full
    assert spec.agent_server.module == Full
    assert spec.agent_server.options == [server_option: :server]
    assert spec.agent_server.dispatch?
    assert spec.agent_server.runtime?

    assert spec.persistence.package == Full
    assert spec.persistence.module == Full
    assert spec.persistence.options == [persistence_option: :store]
    assert spec.persistence.vsn == 3
  end

  @tag obligation: ["jido.plugin.I5", "jido.plugin.I6"]
  test "paired callbacks and owned values are required" do
    for package <- [DumpOnly, LoadOnly] do
      assert {:error, %{details: %{plugin: ^package}}} =
               Normalizer.normalize_all([package])
    end

    for package <- [QuiesceOnly, ResumeOnly] do
      assert {:error, %{details: %{plugin: ^package}}} = Normalizer.normalize_all([package])
    end

    assert {:error, %{details: %{plugin: UnownedDispatch}}} =
             Normalizer.normalize_all([UnownedDispatch])

    assert {:error, %{details: %{plugin: UnhandledDirective}}} =
             Normalizer.normalize_all([UnhandledDirective])
  end

  @tag obligation: "jido.plugin.I5"
  test "removed callback forms and dynamic state schemas are rejected" do
    assert {:error,
            %{details: %{plugin: LegacyDirectiveValidation, callback: {:validate_directive, 2}}}} =
             Normalizer.normalize_all([LegacyDirectiveValidation])

    assert {:error, %{details: %{plugin: LegacyStateUpdate, callback: {:update_state, 3}}}} =
             Normalizer.normalize_all([LegacyStateUpdate])

    assert {:error, %{details: %{plugin: DynamicSchema, state_key: :dynamic, reason: _reason}}} =
             Normalizer.normalize_all([DynamicSchema])
  end

  @tag obligation: "jido.plugin.I5"
  test "Agent callback declarations require safe state and Directive ownership" do
    for {state_spec, detail} <- [
          {{nil, Zoi.integer()}, {:state_key, nil}},
          {{:__struct__, Zoi.integer()}, {:state_key, :__struct__}},
          {{"owned", Zoi.integer()}, {:value, {"owned", Zoi.integer()}}},
          {{:owned, %URI{}}, {:schema, %URI{}}},
          {:invalid, {:value, :invalid}}
        ] do
      assert {:error, %{details: details}} =
               Normalizer.normalize_all([
                 {Configurable, state_spec: state_spec, validation: :ok}
               ])

      assert details.plugin == Configurable
      assert Map.fetch!(details, elem(detail, 0)) == elem(detail, 1)
    end

    for {directives, detail} <- [
          {:invalid, {:directives, :invalid}},
          {[42], {:directives, [42]}},
          {[Effect, Effect], {:directives, [Effect, Effect]}},
          {[JidoTest.MissingGenericDirective], {:directive, JidoTest.MissingGenericDirective}},
          {[String], {:directive, String}},
          {[ValidatorWithoutStruct], {:directive, ValidatorWithoutStruct}},
          {[PlainStruct], {:directive, PlainStruct}}
        ] do
      assert {:error, %{details: details}} =
               Normalizer.normalize_all([
                 {Configurable, directives: directives, validation: :ok}
               ])

      assert details.plugin == Configurable
      assert Map.fetch!(details, elem(detail, 0)) == elem(detail, 1)
    end

    assert {:error, %{details: %{plugin: Configurable}}} =
             Normalizer.normalize_all([
               {Configurable, directives: [Jido.Agent.Directive.Emit], validation: :ok}
             ])

    assert {:error, %{details: %{state_key: :owned}}} =
             Normalizer.normalize_all([
               {Configurable, validation: :ok},
               SameStateOwner
             ])

    assert {:error, %{details: %{directive: Effect}}} =
             Normalizer.normalize_all([
               {Configurable, validation: :ok},
               OtherOwner
             ])
  end

  @tag obligation: ["jido.plugin.I6", "jido.plugin.I7"]
  test "option validation preserves explicit errors and contains faults" do
    expected = Jido.Error.validation_error("rejected")

    assert {:error, ^expected} =
             Normalizer.normalize_all([{Configurable, validation: {:error, expected}}])

    assert {:error, :rejected} =
             Normalizer.normalize_all([{Configurable, validation: {:error, :rejected}}])

    assert {:error, invalid} =
             Normalizer.normalize_all([{Configurable, validation: :invalid}])

    assert invalid.details.code == :plugin_invalid_callback_result
    assert invalid.details.plugin == Configurable
    assert invalid.details.result == :invalid

    for failure <- [:raise, :throw, :exit] do
      assert {:error, fault} =
               Normalizer.normalize_all([{Configurable, validation: failure}])

      assert fault.details.code == :plugin_callback_failed
      assert fault.details.plugin == Configurable
      assert fault.details.callback == :validate_options

      case failure do
        :raise -> assert %ArgumentError{} = fault.details.error
        kind -> assert %{kind: ^kind, reason: :bad_plugin_options} = fault.details
      end
    end
  end

  @tag obligation: "jido.plugin.I7"
  test "state and Directive callbacks preserve explicit errors" do
    expected = Jido.Error.validation_error("state rejected")

    assert {:error, ^expected} =
             Normalizer.normalize_all([{StateResult, result: {:error, expected}}])

    assert {:ok, [error_key]} =
             Normalizer.normalize_all([{StateResult, result: {:error, Zoi.integer()}}])

    assert error_key.agent.state_key == :error

    assert {:error, :directives_rejected} =
             Normalizer.normalize_all([
               {Configurable, directives: {:error, :directives_rejected}, validation: :ok}
             ])
  end

  @tag obligation: "jido.plugin.I5"
  test "Directive lookup returns only the Plugin that declared the type" do
    assert {:ok, [spec]} = Normalizer.normalize_all([{Configurable, validation: :ok}])
    assert {:ok, [server]} = Normalizer.normalize_all([ServerOnly])
    assert Plugin.directive_owner([spec], %Effect{}) == spec
    assert Plugin.directive_owner([server, spec], %Effect{}) == spec
    assert Plugin.directive_owner([spec], %PlainStruct{}) == nil
    assert Plugin.directive_owner(:invalid, %Effect{}) == nil
  end
end

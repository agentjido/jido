defmodule JidoTest.Agent.CompatibilityTest do
  use ExUnit.Case, async: true

  import ExUnit.CaptureIO

  alias Jido.Agent
  alias Jido.Agent.Plugin
  alias Jido.Agent.PluginDefaults
  alias Jido.Signal.Router.Route

  defmodule CompatAction do
    @moduledoc false
    use Jido.Action, name: "compat_action", schema: []

    @impl true
    def run(_params, _context), do: {:ok, %{handled: true}}
  end

  defmodule CompatPlugin do
    @moduledoc false

    use Jido.Plugin,
      name: "compat_plugin",
      state_key: :compat_plugin,
      actions: [CompatAction],
      schema: Zoi.object(%{enabled: Zoi.boolean() |> Zoi.default(true)})
  end

  defmodule CompatJido do
    @moduledoc false
    def __default_plugins__, do: [CompatPlugin]
  end

  defmodule KeywordAgent do
    @moduledoc false

    use Jido.Agent,
      name: "keyword_compat_agent",
      schema: Zoi.object(%{count: Zoi.integer() |> Zoi.default(0)}),
      plugins: [{CompatPlugin, enabled: false}],
      signal_routes: [{"compat.run", CompatAction}],
      default_plugins: false
  end

  defmodule DefaultOverrideAgent do
    @moduledoc false

    use Jido.Agent,
      name: "default_override_agent",
      jido: CompatJido,
      default_plugins: %{compat_plugin: {CompatPlugin, enabled: false}}
  end

  test "keyword aliases and old plugin forms lower to canonical values" do
    definition = KeywordAgent.agent()

    assert %Agent{} = definition
    assert %Zoi.Types.Map{} = definition.state_schema
    assert %PluginDefaults{mode: :none} = definition.plugin_defaults
    assert [%Plugin{module: CompatPlugin, config: %{enabled: false}}] = definition.plugins
    assert [%Route{path: "compat.run", target: CompatAction}] = definition.routes
  end

  test "current default plugin maps lower to a canonical policy" do
    assert %PluginDefaults{mode: :inherit, overrides: overrides} =
             DefaultOverrideAgent.agent().plugin_defaults

    assert %Plugin{module: CompatPlugin, config: %{enabled: false}} =
             overrides.compat_plugin
  end

  test "generated new creates an instance and validate remains a state shim" do
    instance = KeywordAgent.new(id: "compat-1", state: %{count: 3})

    assert %Agent{id: "compat-1", agent_module: KeywordAgent, state: %{count: 3}} = instance
    assert Agent.definition(instance) == KeywordAgent.agent()
    assert {:ok, ^instance} = KeywordAgent.validate(instance)

    invalid = KeywordAgent.new(state: %{count: "invalid"})

    assert {:error, %Jido.Error.ValidationError{message: "State validation failed"}} =
             KeywordAgent.validate(invalid)
  end

  test "Direct strategy warns and does not change canonical equality" do
    suffix = System.unique_integer([:positive])
    plain_module = Module.concat(__MODULE__, "Plain#{suffix}")
    direct_module = Module.concat(__MODULE__, "Direct#{suffix}")

    warning =
      capture_io(:stderr, fn ->
        Code.compile_string("""
        defmodule #{inspect(plain_module)} do
          use Jido.Agent,
            name: "strategy_compat_agent",
            category: "catalog",
            tags: ["compat"],
            vsn: "3.0.0"
        end

        defmodule #{inspect(direct_module)} do
          use Jido.Agent,
            name: "strategy_compat_agent",
            strategy: Jido.Agent.Strategy.Direct
        end
        """)
      end)

    assert warning =~ "the Direct strategy option is obsolete"
    assert plain_module.agent() == direct_module.agent()
    assert plain_module.agent().metadata == %{}
    assert plain_module.category() == "catalog"
    assert plain_module.tags() == ["compat"]
    assert plain_module.vsn() == "3.0.0"
  end

  test "custom strategy declarations fail with direct migration help" do
    suffix = System.unique_integer([:positive])
    module = Module.concat(__MODULE__, "Custom#{suffix}")

    assert_raise CompileError,
                 ~r/custom Agent strategies are not supported by v3 authoring.*trusted runtime module binding/,
                 fn ->
                   Code.compile_string("""
                   defmodule #{inspect(module)} do
                     use Jido.Agent,
                       name: "custom_strategy_compat_agent",
                       strategy: Jido.Agent.Strategy.FSM
                   end
                   """)
                 end
  end
end

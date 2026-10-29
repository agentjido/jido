defmodule Jido.Plugin.AuthoringTest do
  use Covenant.Case, component: "jido.plugin", async: true

  alias Jido.Plugin.Normalizer

  defmodule Empty do
    use Jido.Plugin
  end

  defmodule Combined do
    use Jido.Plugin
    def state_spec(_opts), do: :none
    def after_commit(_runtime, _commit, _opts), do: :ok
  end

  defmodule EmptyServer do
    use Jido.Plugin
    def validate_options(_opts), do: :ok
  end

  defmodule UnpairedDispatch do
    use Jido.Plugin
    def dispatch(_runtime, _directive, _context, _opts), do: :ok
  end

  defmodule UnpairedPersistence do
    use Jido.Plugin
    def dump(value, _context, _opts), do: {:ok, value}
    def load(value, _context, _opts), do: {:ok, value}
  end

  defmodule StatelessReducer do
    use Jido.Plugin
    def reduce(_reduction, _opts), do: {:ok, 1}
  end

  defmodule Effect do
    use Jido.Agent.Directive
    defstruct [:value]

    @impl true
    def validate(%__MODULE__{} = directive), do: {:ok, directive}
  end

  defmodule FirstOwner do
    use Jido.Plugin
    def state_spec(_opts), do: {:first, Zoi.integer() |> Zoi.default(0)}
    def directives(_opts), do: [Effect]
    def reduce(reduction, _opts), do: {:ok, reduction.plugin_state}
  end

  defmodule OtherOwner do
    use Jido.Plugin
    def state_spec(_opts), do: {:other, Zoi.object(%{}) |> Zoi.default(%{})}
    def directives(_opts), do: [Effect]
    def reduce(reduction, _opts), do: {:ok, reduction.plugin_state}
  end

  defmodule ArbitraryNames do
    use Jido.Plugin
    def state_spec(_opts), do: :none
    def start_link(_opts), do: {:error, :not_a_runtime}
    def handle_call(_request, _from, state), do: {:reply, :ok, state}
  end

  defmodule EmptyId do
    use Jido.Plugin, id: ""
    def state_spec(_opts), do: :none
  end

  defmodule OneCharacterId do
    use Jido.Plugin, id: "x"
    def state_spec(_opts), do: :none
  end

  defmodule SupportedOptions do
    use Jido.Plugin,
      id: "contract.supported-options",
      vsn: 2,
      option_keys: [agent: [:limit]],
      sections: []

    def state_spec(_opts), do: :none
  end

  @tag obligation: "jido.plugin.I1"
  test "old role and facet selectors are rejected" do
    for options <- [
          "roles: [:unknown]",
          "roles: [:agent, :agent]",
          "roles: :agent",
          "roles: [:agent], agent: SomeFacet",
          "roles: []",
          "agent: SomeFacet",
          "agent_server: SomeFacet",
          "persistence: SomeFacet",
          "topology: SomeFacet"
        ] do
      assert_raise ArgumentError, fn ->
        Code.compile_string("""
        defmodule InvalidRoleDeclaration do
          use Jido.Plugin, #{options}
        end
        """)
      end
    end
  end

  @tag obligation: ["jido.plugin.I1", "jido.plugin.I3"]
  test "use options reject duplicate and malformed declaration metadata" do
    invalid_options = [
      "id: \"one\", id: \"two\"",
      "option_keys: [agent: [:one], agent: [:two]]",
      "option_keys: [agent: [:one, :one]]",
      "option_keys: [unknown: []]",
      "option_keys: :invalid",
      "[:invalid]",
      "%{id: \"invalid\"}"
    ]

    for {options, index} <- Enum.with_index(invalid_options) do
      module = Module.concat(__MODULE__, "InvalidOptions#{index}")

      assert_raise ArgumentError, fn ->
        Code.compile_string("""
        defmodule #{inspect(module)} do
          use Jido.Plugin, #{options}
        end
        """)
      end
    end

    assert {:error,
            %{
              message: "Plugin authoring identity is invalid",
              details: %{
                plugin: EmptyId,
                id: "",
                vsn: 1,
                manifest_vsn: 1,
                authoring: %{id: "", kind: :plugin, target: EmptyId, vsn: 1}
              }
            }} =
             Normalizer.normalize_all([EmptyId])
  end

  @tag obligation: ["jido.plugin.I1", "jido.plugin.I3"]
  test "all supported use options retain their exact metadata" do
    assert SupportedOptions.id() == "contract.supported-options"
    assert SupportedOptions.vsn() == 2

    assert %{option_keys: %{agent: [:limit]}} = SupportedOptions.__jido_plugin__()

    assert {:ok, [spec]} = Normalizer.normalize_all([{SupportedOptions, limit: 1}])
    assert spec.options === [limit: 1]
    assert spec.agent.options === [limit: 1]

    assert {:ok, [%{module: OneCharacterId}]} = Normalizer.normalize_all([OneCharacterId])

    module = Module.concat(__MODULE__, "DynamicSupported#{System.unique_integer([:positive])}")

    Code.compile_quoted(
      quote do
        defmodule unquote(module) do
          use Jido.Plugin,
            id: "contract.dynamic-supported",
            vsn: 2,
            option_keys: [agent: [:limit]],
            sections: []

          def state_spec(_opts), do: :none
        end
      end
    )

    assert module.id() == "contract.dynamic-supported"
    assert module.vsn() == 2
    assert %{option_keys: %{agent: [:limit]}} = module.__jido_plugin__()
  end

  @tag obligation: ["jido.plugin.I1", "jido.plugin.I7"]
  test "runtime manifests are derived from Plugin callbacks" do
    refute function_exported?(Empty, :__jido_plugin__, 0)

    assert function_exported?(Combined, :__jido_plugin__, 0)
  end

  @tag obligation: ["jido.plugin.I1", "jido.plugin.I5", "jido.plugin.I6"]
  test "callbacks retain capability and pairing checks" do
    for {package, details} <- [
          {Empty, %{plugin: Empty}},
          {EmptyServer, %{plugin: EmptyServer, owner: :agent_server}},
          {UnpairedDispatch, %{plugin: UnpairedDispatch}},
          {UnpairedPersistence, %{plugin: UnpairedPersistence}},
          {StatelessReducer, %{plugin: StatelessReducer}}
        ] do
      assert {:error, %Jido.Error.ValidationError{details: actual}} =
               Normalizer.normalize_all([package])

      assert Map.take(actual, Map.keys(details)) == details
    end
  end

  @tag obligation: "jido.plugin.I2"
  test "documented callbacks select their owners without role declarations" do
    assert {:ok, [spec]} = Normalizer.normalize_all([Combined])
    assert spec.agent.module == Combined
    assert spec.agent_server.module == Combined
    assert spec.persistence == nil
    refute Map.has_key?(spec, :topology)
  end

  @tag obligation: "jido.plugin.I2"
  test "arbitrary helper names do not select runtime capabilities" do
    assert {:ok, [spec]} = Normalizer.normalize_all([ArbitraryNames])
    assert spec.agent_server == nil
  end

  @tag obligation: "jido.plugin.I5"
  test "Directive ownership remains unique across Plugins" do
    assert {:error, %Jido.Error.ValidationError{message: message, details: details}} =
             Normalizer.normalize_all([FirstOwner, OtherOwner])

    assert message == "Agent Plugin Directive ownership must be unique"
    assert details.directive == Effect
  end
end

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

defmodule Jido.Plugin.AuthoringTest do
  use ExUnit.Case, async: true

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

  defmodule OtherAudit do
    use Jido.Plugin
    def state_spec(_opts), do: {:other, Zoi.object(%{}) |> Zoi.default(%{})}
    def directives(_opts), do: [Jido.Plugin.Audit.Record]
    def reduce(reduction, _opts), do: {:ok, reduction.plugin_state}
  end

  defmodule ArbitraryNames do
    use Jido.Plugin
    def state_spec(_opts), do: :none
    def start_link(_opts), do: {:error, :not_a_runtime}
    def handle_call(_request, _from, state), do: {:reply, :ok, state}
  end

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

  test "callbacks retain capability and pairing checks" do
    for {package, message} <- [
          {Empty, "Plugin must define at least one callback"},
          {EmptyServer, "Plugin facet defines no capability"},
          {UnpairedDispatch, "Agent Server Plugin dispatch requires Agent-owned Directives"},
          {UnpairedPersistence, "Persistence Plugin facet requires a stateful Agent facet"},
          {StatelessReducer, "Agent Plugin reduce/2 requires state_spec/1"}
        ] do
      assert {:error, %Jido.Error.ValidationError{message: ^message}} =
               Normalizer.normalize_all([package])
    end
  end

  test "documented callbacks select their owners without role declarations" do
    assert {:ok, [spec]} = Normalizer.normalize_all([Combined])
    assert spec.agent.module == Combined
    assert spec.agent_server.module == Combined
    assert spec.persistence == nil
    assert spec.topology == nil
  end

  test "arbitrary helper names do not select runtime capabilities" do
    assert {:ok, [spec]} = Normalizer.normalize_all([ArbitraryNames])
    assert spec.agent_server == nil
  end

  test "Directive ownership remains unique across Plugins" do
    assert {:error, %Jido.Error.ValidationError{message: message, details: details}} =
             Normalizer.normalize_all([Jido.Plugin.Audit, OtherAudit])

    assert message == "Agent Plugin Directive ownership must be unique"
    assert details.directive == Jido.Plugin.Audit.Record
  end
end

defmodule Jido.Plugin.RolesTest do
  use ExUnit.Case, async: true

  alias Jido.Plugin.Normalizer

  defmodule Empty do
    use Jido.Plugin, roles: [:agent]
  end

  defmodule Undeclared do
    use Jido.Plugin, roles: [:agent]
    def state_spec(_opts), do: :none
    def after_commit(_runtime, _commit, _opts), do: :ok
  end

  defmodule EmptyServer do
    use Jido.Plugin, roles: [:agent_server]
    def validate_options(_opts), do: :ok
  end

  defmodule UnpairedDispatch do
    use Jido.Plugin, roles: [:agent_server]
    def dispatch(_runtime, _directive, _context, _opts), do: :ok
  end

  defmodule UnpairedPersistence do
    use Jido.Plugin, roles: [:persistence]
    def dump(value, _context, _opts), do: {:ok, value}
    def load(value, _context, _opts), do: {:ok, value}
  end

  defmodule StatelessReducer do
    use Jido.Plugin, roles: [:agent]
    def reduce(_reduction, _opts), do: {:ok, 1}
  end

  defmodule OtherAudit do
    use Jido.Plugin, roles: [:agent]
    def state_spec(_opts), do: {:other, Zoi.object(%{}) |> Zoi.default(%{})}
    def directives(_opts), do: [Jido.Plugin.Audit.Record]
    def reduce(reduction, _opts), do: {:ok, reduction.plugin_state}
  end

  defmodule ArbitraryNames do
    use Jido.Plugin, roles: [:agent]
    def state_spec(_opts), do: :none
    def start_link(_opts), do: {:error, :not_a_runtime}
    def handle_call(_request, _from, state), do: {:reply, :ok, state}
  end

  test "roles are a closed literal list with one declaration per owner" do
    for options <- [
          "roles: [:unknown]",
          "roles: [:agent, :agent]",
          "roles: :agent",
          "roles: [:agent], agent: SomeFacet",
          "roles: []"
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

  test "declared roles use the existing capability and pairing checks" do
    for {package, message} <- [
          {Empty, "Plugin facet defines no capability"},
          {EmptyServer, "Plugin facet defines no capability"},
          {UnpairedDispatch, "Agent Server Plugin dispatch requires Agent-owned Directives"},
          {UnpairedPersistence, "Persistence Plugin facet requires a stateful Agent facet"},
          {StatelessReducer, "Agent Plugin reduce/2 requires state_spec/1"}
        ] do
      assert {:error, %Jido.Error.ValidationError{message: ^message}} =
               Normalizer.normalize_all([package])
    end
  end

  test "callbacks require their explicit role" do
    assert {:error, %Jido.Error.ValidationError{details: details}} =
             Normalizer.normalize_all([Undeclared])

    assert details == %{plugin: Undeclared, roles: [:agent], callback: {:after_commit, 3}}
  end

  test "arbitrary helper names do not select runtime capabilities" do
    assert {:ok, [spec]} = Normalizer.normalize_all([ArbitraryNames])
    assert spec.agent_server == nil
  end

  test "Directive ownership remains unique across local roles" do
    assert {:error, %Jido.Error.ValidationError{message: message, details: details}} =
             Normalizer.normalize_all([Jido.Plugin.Audit, OtherAudit])

    assert message == "Agent Plugin Directive ownership must be unique"
    assert details.directive == Jido.Plugin.Audit.Record
  end
end

defmodule Jido.Agent.Plugin.DeclarationTest do
  use ExUnit.Case, async: true

  alias Jido.Agent.Plugin.Declaration

  defmodule First do
    use Jido.Plugin, id: "test.declaration.first"
  end

  defmodule Second do
    use Jido.Plugin, id: "test.declaration.second"
  end

  defmodule DuplicateID do
    use Jido.Plugin, id: "test.declaration.first"
  end

  defmodule Runtime do
    use Jido.Plugin, id: "test.declaration.runtime"

    @impl true
    def state_spec(_opts), do: :none
  end

  defmodule ManualProvider do
    def id, do: "test.declaration.manual"
    def vsn, do: 1
    def sections, do: []

    def __jido_authoring__,
      do: %{id: id(), kind: :plugin, target: __MODULE__, vsn: vsn()}

    def lower(_dsl, config), do: {:ok, config}
    def normalize(data), do: {:ok, data}
    def verify(_data, _definition), do: :ok
    def endpoint_kinds, do: []
    def endpoints(_data), do: []
    def verify_connection(_data, _connection), do: :ok
  end

  defmodule Imports do
    defmacro plugin_note(value) do
      quote do
        plugin_notes do
          value(unquote(value))
        end
      end
    end
  end

  defmodule Imported do
    alias Spark.Dsl.Extension

    @section %Spark.Dsl.Section{
      name: :plugin_notes,
      schema: [value: [type: :string, required: true]]
    }

    use Jido.Plugin,
      id: "test.declaration.imported",
      sections: [@section],
      imports: [Imports]

    @impl true
    def lower(dsl, config) do
      note = Extension.get_opt(dsl, [:plugin_notes], :value)
      {:ok, Map.put(config, :note, note)}
    end
  end

  defmodule ImportedAgent do
    use Jido.Agent,
      name: "imported_plugin_agent",
      plugins: [Imported]

    plugin_note("ready")
  end

  test "normalizes bare and configured Plugin declarations in order" do
    assert {:ok,
            [
              %{provider: First, config: %{}},
              %{provider: Second, config: %{mode: :strict}}
            ]} = Declaration.normalize([First, {Second, %{mode: :strict}}])
  end

  test "rejects duplicate Plugin modules and IDs" do
    assert {:error, _error} = Declaration.normalize([First, First])
    assert {:error, _error} = Declaration.normalize([First, DuplicateID])
  end

  test "requires a static config map with atom keys" do
    for declaration <- [
          {First, [mode: :strict]},
          {First, %{"mode" => :strict}},
          {First, %{owner: self()}}
        ] do
      assert {:error, _error} = Declaration.normalize([declaration])
    end
  end

  test "requires the Jido.Plugin behavior at every Agent definition boundary" do
    assert {:error, %{code: :invalid_plugin}} = Declaration.normalize([ManualProvider])

    entry = %{
      id: ManualProvider.id(),
      provider: ManualProvider,
      vsn: ManualProvider.vsn(),
      data: %{}
    }

    assert {:error, %{code: :invalid_plugin, path: [:plugins, 0]}} =
             Jido.Agent.define(%{name: "manual_provider", plugins: [entry]})
  end

  test "installs Plugin imports through Spark module imports" do
    assert [%{provider: Imported, data: %{note: "ready"}}] = ImportedAgent.definition().plugins
  end

  test "creates a runtime manifest only for runtime callbacks" do
    refute function_exported?(First, :__jido_plugin__, 0)
    assert function_exported?(Runtime, :__jido_plugin__, 0)
  end

  test "rejects the removed Agent option and Plugin block" do
    suffix = System.unique_integer([:positive])

    assert_raise Spark.Options.ValidationError, fn ->
      Code.compile_string("""
      defmodule JidoTest.RemovedExtensions#{suffix} do
        use Jido.Agent, name: "removed_extensions", extensions: []
      end
      """)
    end

    ExUnit.CaptureIO.capture_io(:stderr, fn ->
      assert_raise CompileError, fn ->
        Code.compile_string("""
        defmodule JidoTest.RemovedPluginBlock#{suffix} do
          use Jido.Agent, name: "removed_plugin_block"

          plugins do
          end
        end
        """)
      end
    end)
  end
end

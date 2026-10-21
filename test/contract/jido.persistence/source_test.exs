defmodule JidoTest.Persistence.SourceTest do
  use ExUnit.Case, async: false
  use Covenant.Case, component: "jido.persistence", async: false

  alias Jido.Persistence.{ETS, Source}

  defmodule ConfiguredSource do
    def __jido_persistence__,
      do: {Jido.Persistence.ETS, table: :persistence_source_default}
  end

  defmodule DisabledSource do
    def __jido_persistence__, do: nil
  end

  @tag obligation: "jido.persistence.I1"
  test "module and live instance sources resolve one selected adapter" do
    default = {ETS, table: :persistence_source_default}
    assert {:ok, ^default} = Jido.Persistence.resolve_config(:inherit, ConfiguredSource)
    assert {:ok, ^default, ConfiguredSource} = Source.resolve(ConfiguredSource, [])

    live = {ETS, table: :persistence_source_live}
    namespace = "persistence/source/#{System.unique_integer([:positive])}"

    start_supervised!(
      {Jido, name: ConfiguredSource, namespace: namespace, persistence: live},
      id: {Jido, ConfiguredSource}
    )

    assert {:ok, ^live} = Jido.Persistence.resolve_config(:inherit, ConfiguredSource)
    assert {:ok, ^live, ConfiguredSource} = Source.resolve(ConfiguredSource, [])

    assert {:ok, ^live, :explicit_instance} =
             Source.resolve(ConfiguredSource, instance: :explicit_instance)

    runtime_name = :"persistence_source_runtime_#{System.unique_integer([:positive])}"

    start_supervised!(
      {Jido, name: runtime_name, namespace: namespace <> "/runtime", persistence: live},
      id: {Jido, runtime_name}
    )

    assert {:ok, ^live, ^runtime_name} = Source.resolve(runtime_name, [])
  end

  @tag obligation: "jido.persistence.I1"
  test "disabled, missing, and malformed sources fail at the configuration boundary" do
    assert {:ok, nil} = Jido.Persistence.resolve_config(nil, nil)
    assert {:ok, nil} = Jido.Persistence.resolve_config(false, ConfiguredSource)
    assert {:ok, nil} = Jido.Persistence.resolve_config(:inherit, nil)
    assert {:ok, nil} = Jido.Persistence.resolve_config(:inherit, String)
    assert {:ok, nil} = Jido.Persistence.resolve_config(:inherit, 123)
    assert {:ok, nil} = Jido.Persistence.resolve_config(:inherit, DisabledSource)
    assert {:error, :persistence_not_configured} = Source.resolve(nil, [])

    process_name = :"persistence_source_process_#{System.unique_integer([:positive])}"
    process = start_supervised!({Agent, fn -> :ok end}, id: process_name)
    Process.register(process, process_name)

    assert {:error, {:invalid_persistence_adapter, ^process_name}} =
             Source.resolve(process_name, [])

    assert {:error, {:invalid_persistence_options, [:not_keyword]}} =
             Source.validate_operation_options([:not_keyword])

    assert {:error, {:unsupported_persistence_option, :write_authority}} =
             Source.validate_operation_options(write_authority: :removed)
  end
end

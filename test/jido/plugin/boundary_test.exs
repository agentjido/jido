defmodule Jido.Plugin.BoundaryTest do
  use ExUnit.Case, async: true

  alias Jido.Plugin.{Manifest, Spec}

  defmodule OwnedState do
    use Jido.Plugin

    @impl true
    defdelegate state_spec(opts), to: Jido.Plugin.BoundaryTest.OwnedState.Agent

    @impl true
    defdelegate reduce(reduction, opts), to: Jido.Plugin.BoundaryTest.OwnedState.Agent
  end

  defmodule OwnedState.Agent do
    @behaviour Jido.Plugin

    def state_spec(_opts), do: {:owned, Zoi.integer() |> Zoi.default(3)}
    def reduce(reduction, _opts), do: {:ok, reduction.plugin_state}
  end

  defmodule Empty do
    use Jido.Plugin
  end

  defmodule StatelessReducer do
    use Jido.Plugin
    def reduce(_reduction, _opts), do: {:ok, 1}
  end

  defmodule RaisingMetadata do
    def __jido_plugin__, do: raise(ArgumentError, "metadata is unavailable")
  end

  defmodule ThrowingMetadata do
    def __jido_plugin__, do: throw(:metadata_unavailable)
  end

  defmodule TamperedMetadata do
    @behaviour Jido.Plugin
    def __jido_plugin__, do: %Manifest{module: __MODULE__, agent: __MODULE__}
    def state_spec(_opts), do: :none
    def after_commit(_, _, _), do: :ok
  end

  defmodule MismatchedPackage do
    def __jido_plugin__, do: %Manifest{module: OwnedState, agent: OwnedState}
  end

  defmodule RuntimePackage do
    use Jido.Plugin
    def admit(_runtime, _admission, opts), do: {:ok, opts}
  end

  test "stored specs without a manifest are rejected" do
    stored = %Spec{module: OwnedState, options: [label: "stored"]}

    assert {:error, %{message: "Plugin specs require a manifest"}} =
             Jido.Plugin.Normalizer.normalize_all([stored])

    assert {:ok, [spec]} = Jido.Plugin.Normalizer.normalize_all([OwnedState])
    assert {:ok, [^spec]} = Jido.Plugin.Normalizer.normalize_all([spec])
  end

  test "manifest accessors retain owner order and restrict mapped options" do
    manifest = %Manifest{
      module: RuntimePackage,
      agent: RuntimePackage,
      agent_server: RuntimePackage,
      option_keys: %{agent_server: [:result]}
    }

    assert Manifest.owners() == [:agent, :agent_server, :persistence]

    assert Enum.map(Manifest.owners(), &Manifest.facet(manifest, &1)) ==
             [RuntimePackage, RuntimePackage, nil]

    options = [result: {:error, :unavailable}]
    assert {:ok, ^manifest} = Manifest.validate(manifest, options)
    assert Manifest.options_for(manifest, :agent, options) == []
    assert Manifest.options_for(manifest, :agent_server, options) == options
    assert Manifest.options_for(%{manifest | option_keys: %{}}, :agent, options) == options
  end

  test "invalid manifest identities and versions return configuration errors" do
    manifest = %Manifest{module: RuntimePackage, agent_server: RuntimePackage}

    for {field, value, message} <- [
          {:module, nil, "Plugin package module is invalid"},
          {:module, "plugin", "Plugin package module is invalid"},
          {:vsn, 0, "Plugin package version must be positive"},
          {:vsn, "1", "Plugin package version must be positive"},
          {:agent_server, nil, "Plugin must define at least one callback"},
          {:agent_server, "facet", "Plugin callbacks must belong to the Plugin module"},
          {:agent_server, false, "Plugin callbacks must belong to the Plugin module"}
        ] do
      assert {:error, %Jido.Error.ValidationError{message: ^message, kind: :config}} =
               Manifest.validate(Map.put(manifest, field, value), [])
    end

    for {value, options} <- [{%{}, []}, {manifest, %{result: :ok}}] do
      assert {:error, %Jido.Error.ValidationError{details: details}} =
               Manifest.validate(value, options)

      assert details == %{manifest: value, options: options}
    end
  end

  test "manifest option mappings reject duplicate keys and unassigned options" do
    manifest = %Manifest{module: RuntimePackage, agent_server: RuntimePackage}

    for mapping <- [%{agent_server: [:result, :result]}, %{agent_server: ["result"]}] do
      assert {:error, %Jido.Error.ValidationError{} = error} =
               Manifest.validate(%{manifest | option_keys: mapping}, [])

      assert error.message == "Plugin option mapping must contain unique atom keys"
      assert error.details.mapping == {:agent_server, mapping.agent_server}
    end

    assert {:error, %{message: "Plugin option mapping must be a map"}} =
             Manifest.validate(%{manifest | option_keys: []}, [])

    assert {:error, %{details: %{options: [:unknown]}}} =
             Manifest.validate(%{manifest | option_keys: %{agent_server: [:result]}}, unknown: 1)

    assert {:error, %{message: "Plugin declaration options must be static data"}} =
             Manifest.validate(manifest, result: self())
  end

  test "normalization rejects mismatched metadata and invalid callback combinations" do
    assert {:error, %{details: %{plugin: MismatchedPackage, manifest: OwnedState}}} =
             Jido.Plugin.Normalizer.normalize_all([MismatchedPackage])

    assert {:error, %{message: "Plugin must define at least one callback"}} =
             Jido.Plugin.Normalizer.normalize_all([Empty])

    assert {:error, %{message: "Agent Plugin reduce/2 requires state_spec/1"}} =
             Jido.Plugin.Normalizer.normalize_all([StatelessReducer])

    assert {:error, %{message: "Plugin manifest must match its documented callbacks"}} =
             Jido.Plugin.Normalizer.normalize_all([TamperedMetadata])
  end

  test "package metadata exceptions are contained at the normalization boundary" do
    for package <- [RaisingMetadata, ThrowingMetadata] do
      assert {:error,
              %Jido.Error.ExecutionError{message: "Agent Plugin marker failed", details: details}} =
               Jido.Plugin.Normalizer.normalize_all([package])

      assert details.plugin == package
      assert details.callback == :__jido_plugin__
    end
  end
end

defmodule Jido.Plugin.BoundaryTest do
  use Covenant.Case, component: "jido.plugin", async: true

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

  defmodule CallbackOnly do
    def state_spec(_opts), do: :none
  end

  defmodule MarkerOnly do
    def __jido_plugin__, do: %Manifest{module: __MODULE__, agent: __MODULE__}
    def state_spec(_opts), do: :none
  end

  defmodule ForgedPackage do
    @behaviour Jido.Plugin
    def __jido_plugin__, do: %Manifest{module: __MODULE__, agent: __MODULE__}
    def state_spec(_opts), do: :none
  end

  defmodule ExtensionOnly do
    use Jido.Agent.Extension, id: "contract.extension-only", kind: :plugin

    def runtime_support, do: __MODULE__
    def __jido_plugin__, do: %Manifest{module: __MODULE__, agent: __MODULE__}
    def state_spec(_opts), do: :none
  end

  defmodule RuntimePackage do
    use Jido.Plugin
    def admit(_runtime, _admission, opts), do: {:ok, opts}
  end

  @tag obligation: "jido.plugin.I4"
  test "stored specs without a manifest are rejected" do
    stored = %Spec{module: OwnedState, options: [label: "stored"]}

    assert {:error, %{message: "Plugin specs require a manifest", details: %{specs: [^stored]}}} =
             Jido.Plugin.Normalizer.normalize_all([stored])

    assert {:ok, [spec]} = Jido.Plugin.Normalizer.normalize_all([OwnedState])
    assert {:ok, [^spec]} = Jido.Plugin.Normalizer.normalize_all([spec])
  end

  @tag obligation: "jido.plugin.I4"
  test "stored specs require a module and options" do
    for source <- [
          "%Jido.Plugin.Spec{options: []}",
          "%Jido.Plugin.Spec{module: String}"
        ] do
      assert_raise ArgumentError, fn -> Code.eval_string(source) end
    end
  end

  @tag obligation: ["jido.plugin.I2", "jido.plugin.I3"]
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

    assert_raise FunctionClauseError, fn -> apply(Manifest, :facet, [manifest, :unknown]) end

    assert_raise FunctionClauseError, fn ->
      apply(Manifest, :options_for, [manifest, :unknown, options])
    end

    assert_raise FunctionClauseError, fn ->
      apply(Manifest, :options_for, [manifest, :agent, %{}])
    end

    assert_raise ArgumentError, fn -> Manifest.options_for(manifest, :agent, [:invalid]) end

    assert_raise ArgumentError, fn -> struct!(Manifest, []) end
  end

  @tag obligation: "jido.plugin.I3"
  test "invalid manifest identities and versions return configuration errors" do
    manifest = %Manifest{module: RuntimePackage, agent_server: RuntimePackage}

    for {field, value, details} <- [
          {:module, nil, %{module: nil}},
          {:module, true, %{module: true}},
          {:module, false, %{module: false}},
          {:module, "plugin", %{module: "plugin"}},
          {:vsn, 0, %{vsn: 0}},
          {:vsn, "1", %{vsn: "1"}},
          {:agent_server, nil, %{plugin: RuntimePackage}},
          {:agent_server, "facet", %{plugin: RuntimePackage, facet: "facet"}},
          {:agent_server, false, %{plugin: RuntimePackage, facet: false}}
        ] do
      assert {:error, %Jido.Error.ValidationError{kind: :config, details: ^details}} =
               Manifest.validate(Map.put(manifest, field, value), [])
    end

    for {value, options} <- [{%{}, []}, {manifest, %{result: :ok}}] do
      assert {:error, %Jido.Error.ValidationError{details: details}} =
               Manifest.validate(value, options)

      assert details == %{manifest: value, options: options}
    end
  end

  @tag obligation: "jido.plugin.I3"
  test "manifest option mappings reject duplicate keys and unassigned options" do
    manifest = %Manifest{module: RuntimePackage, agent_server: RuntimePackage}

    for mapping <- [%{agent_server: [:result, :result]}, %{agent_server: ["result"]}] do
      assert {:error, %Jido.Error.ValidationError{} = error} =
               Manifest.validate(%{manifest | option_keys: mapping}, [])

      assert error.message == "Plugin option mapping must contain unique atom keys"
      assert error.details.mapping == {:agent_server, mapping.agent_server}
    end

    assert {:error,
            %{
              message: "Plugin option mapping must be a map",
              details: %{option_keys: []}
            }} =
             Manifest.validate(%{manifest | option_keys: []}, [])

    assert {:error, %{details: %{owner: :unknown, owners: owners}}} =
             Manifest.validate(%{manifest | option_keys: %{unknown: []}}, [])

    assert owners == Manifest.owners()

    assert {:error, %{details: %{owner: :agent}}} =
             Manifest.validate(%{manifest | option_keys: %{agent: []}}, [])

    assert {:error, %{details: %{options: [:unknown]}}} =
             Manifest.validate(%{manifest | option_keys: %{agent_server: [:result]}}, unknown: 1)

    assert {:error, %{details: %{reason: _reason}}} =
             Manifest.validate(manifest, result: self())

    assert {:error,
            %{
              message: "Plugin declaration options must be unique",
              details: %{options: [:result]}
            }} = Manifest.validate(manifest, result: :first, result: :second)

    assert {:error, %{details: %{manifest: ^manifest, options: [:invalid]}}} =
             Manifest.validate(manifest, [:invalid])
  end

  @tag obligation: [
         "jido.plugin.I1",
         "jido.plugin.I2",
         "jido.plugin.I4",
         "jido.plugin.I5",
         "jido.plugin.I6"
       ]
  test "normalization rejects mismatched metadata and invalid callback combinations" do
    assert {:error, %{details: %{plugin: MismatchedPackage, manifest: OwnedState}}} =
             Jido.Plugin.Normalizer.normalize_all([MismatchedPackage])

    assert {:error, %{message: "Plugin must define at least one callback"}} =
             Jido.Plugin.Normalizer.normalize_all([Empty])

    assert {:error, %{message: "Agent Plugin reduce/2 requires state_spec/1"}} =
             Jido.Plugin.Normalizer.normalize_all([StatelessReducer])

    assert {:error,
            %{
              message: "Plugin manifest must match its documented callbacks",
              details: %{plugin: TamperedMetadata, owner: :agent_server}
            }} =
             Jido.Plugin.Normalizer.normalize_all([TamperedMetadata])

    for package <- [CallbackOnly, MarkerOnly, ForgedPackage, ExtensionOnly, String] do
      assert {:error, %{details: %{plugin: ^package}}} =
               Jido.Plugin.Normalizer.normalize_all([package])
    end
  end

  @tag obligation: "jido.plugin.I7"
  test "package metadata exceptions are contained at the normalization boundary" do
    for package <- [RaisingMetadata, ThrowingMetadata] do
      assert {:error,
              %Jido.Error.ExecutionError{message: "Agent Plugin marker failed", details: details}} =
               Jido.Plugin.Normalizer.normalize_all([package])

      assert details.plugin == package
      assert details.callback == :__jido_plugin__

      case package do
        RaisingMetadata -> assert %ArgumentError{} = details.error
        ThrowingMetadata -> assert %{kind: :throw, reason: :metadata_unavailable} = details
      end
    end
  end
end

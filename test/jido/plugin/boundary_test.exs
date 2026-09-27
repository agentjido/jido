defmodule Jido.Plugin.BoundaryTest do
  use ExUnit.Case, async: true

  alias Jido.Plugin.{Manifest, Spec}
  alias Jido.Topology.Plugin, as: TopologyPlugin
  alias Jido.Topology.Plugin.Contribution

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

  defmodule TopologyFacet do
    @behaviour Jido.Plugin

    def contribute(context, opts) do
      case Keyword.fetch!(opts, :result) do
        :invalid_shape -> {:ok, %Contribution{plugin: context.plugin, resources: :invalid}}
        :wrong_owner -> {:ok, %Contribution{plugin: OwnedState}}
        :raise -> raise ArgumentError, "invalid topology input"
        :throw -> throw(:invalid_topology_input)
        result -> result
      end
    end
  end

  defmodule TopologyPackage do
    use Jido.Plugin

    @impl true
    defdelegate contribute(context, opts), to: Jido.Plugin.BoundaryTest.TopologyFacet
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
      module: TopologyPackage,
      agent: TopologyPackage,
      topology: TopologyPackage,
      option_keys: %{topology: [:result]}
    }

    assert Manifest.owners() == [:agent, :agent_server, :persistence, :topology]

    assert Enum.map(Manifest.owners(), &Manifest.facet(manifest, &1)) ==
             [TopologyPackage, nil, nil, TopologyPackage]

    options = [result: {:error, :unavailable}]
    assert {:ok, ^manifest} = Manifest.validate(manifest, options)
    assert Manifest.options_for(manifest, :agent, options) == []
    assert Manifest.options_for(manifest, :topology, options) == options
    assert Manifest.options_for(%{manifest | option_keys: %{}}, :agent, options) == options
  end

  test "invalid manifest identities and versions return configuration errors" do
    manifest = %Manifest{module: TopologyPackage, topology: TopologyPackage}

    for {field, value, message} <- [
          {:module, nil, "Plugin package module is invalid"},
          {:module, "plugin", "Plugin package module is invalid"},
          {:vsn, 0, "Plugin package version must be positive"},
          {:vsn, "1", "Plugin package version must be positive"},
          {:topology, nil, "Plugin must define at least one callback"},
          {:topology, "facet", "Plugin callbacks must belong to the Plugin module"},
          {:topology, false, "Plugin callbacks must belong to the Plugin module"}
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
    manifest = %Manifest{module: TopologyPackage, topology: TopologyPackage}

    for mapping <- [%{topology: [:result, :result]}, %{topology: ["result"]}] do
      assert {:error, %Jido.Error.ValidationError{} = error} =
               Manifest.validate(%{manifest | option_keys: mapping}, [])

      assert error.message == "Plugin option mapping must contain unique atom keys"
      assert error.details.mapping == {:topology, mapping.topology}
    end

    assert {:error, %{message: "Plugin option mapping must be a map"}} =
             Manifest.validate(%{manifest | option_keys: []}, [])

    assert {:error, %{details: %{options: [:unknown]}}} =
             Manifest.validate(%{manifest | option_keys: %{topology: [:result]}}, unknown: 1)

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

  test "Topology returns explicit errors and contains callback exceptions" do
    assert topology_result({:error, :unavailable}) == {:error, :unavailable}

    for result <- [:raise, :throw] do
      assert {:error, %Jido.Error.ExecutionError{details: details}} = topology_result(result)
      assert details.code == :plugin_callback_failed
      assert details.callback == :contribute
      assert details.plugin == TopologyPackage
      refute Map.has_key?(details, :facet)
    end
  end

  test "Topology rejects invalid result shapes and changed contribution ownership" do
    for {result, message} <- [
          {:unexpected, "Topology Plugin contribute/2 returned an invalid result"},
          {{:ok, %{}}, "Topology Plugin contribute/2 returned an invalid result"},
          {:invalid_shape, "Topology Plugin returned an invalid contribution"},
          {:wrong_owner, "Topology Plugin contribution changed package identity"}
        ] do
      assert {:error, %Jido.Error.ExecutionError{message: ^message, details: details}} =
               topology_result(result)

      assert details.code == :plugin_invalid_callback_result
      assert details.plugin == TopologyPackage
      refute Map.has_key?(details, :facet)

      if result == :wrong_owner, do: assert(details.actual == OwnedState)
      if result == :invalid_shape, do: assert(%Jido.Error.ValidationError{} = details.reason)
    end
  end

  test "Topology contribution contexts enforce static identity fields" do
    {:ok, [spec]} = Jido.Plugin.Normalizer.normalize_all([TopologyPackage])
    context = TopologyPlugin.context(spec, "agent/worker", __MODULE__)
    assert {:ok, ^context} = Jido.Topology.Plugin.Context.validate(context)
    assert {:ok, ^context} = Zoi.parse(Jido.Topology.Plugin.Context.schema(), context)

    for invalid <- [%{context | plugin_vsn: 0}, %{context | agent_key: ""}] do
      assert {:error,
              %{message: "Topology Plugin context is invalid", details: %{issues: [_ | _]}}} =
               Jido.Topology.Plugin.Context.validate(invalid)
    end

    assert {:error, %{details: %{value: %{}}}} = Jido.Topology.Plugin.Context.validate(%{})
  end

  defp topology_result(result) do
    {:ok, [spec]} = Jido.Plugin.Normalizer.normalize_all([{TopologyPackage, result: result}])
    context = TopologyPlugin.context(spec, "worker", __MODULE__)
    TopologyPlugin.contribute(spec, context)
  end
end

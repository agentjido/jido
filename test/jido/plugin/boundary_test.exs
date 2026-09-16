defmodule Jido.Plugin.BoundaryTest do
  use ExUnit.Case, async: true

  alias Jido.Plugin
  alias Jido.Plugin.{Manifest, Spec}
  alias Jido.Topology.Plugin, as: TopologyPlugin
  alias Jido.Topology.Plugin.Contribution

  defmodule OwnedState do
    use Jido.Plugin, agent: __MODULE__.Agent
  end

  defmodule OwnedState.Agent do
    use Jido.Agent.Plugin

    def state_spec(_opts), do: {:owned, Zoi.integer() |> Zoi.default(3)}
    def reduce(reduction, _opts), do: {:ok, reduction.plugin_state}
  end

  defmodule EmptyAgentFacet do
    use Jido.Agent.Plugin
  end

  defmodule EmptyServerFacet do
    use Jido.AgentServer.Plugin
  end

  defmodule StatelessReducer do
    use Jido.Agent.Plugin

    def reduce(_reduction, _opts), do: {:ok, 1}
  end

  defmodule RaisingMetadata do
    @behaviour Jido.Agent.Plugin

    def __jido_plugin_facet__, do: raise(ArgumentError, "facet metadata is unavailable")
    def state_spec(_opts), do: :none
  end

  defmodule ThrowingMetadata do
    @behaviour Jido.Agent.Plugin

    def __jido_plugin_facet__, do: throw(:facet_metadata_unavailable)
    def state_spec(_opts), do: :none
  end

  for {package, owner, facet} <- [
        {EmptyAgentPackage, :agent, EmptyAgentFacet},
        {EmptyServerPackage, :agent_server, EmptyServerFacet},
        {StatelessReducerPackage, :agent, StatelessReducer},
        {RaisingMetadataPackage, :agent, RaisingMetadata},
        {ThrowingMetadataPackage, :agent, ThrowingMetadata},
        {WrongPersistencePackage, :persistence, EmptyAgentFacet}
      ] do
    defmodule package do
      @manifest %Manifest{module: __MODULE__} |> Map.put(owner, facet)
      def __jido_plugin__, do: @manifest
    end
  end

  defmodule MismatchedPackage do
    def __jido_plugin__, do: %Manifest{module: OwnedState, agent: EmptyAgentFacet}
  end

  defmodule TopologyFacet do
    use Jido.Topology.Plugin

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
    use Jido.Plugin, topology: TopologyFacet
  end

  test "stored specs without a manifest are rejected" do
    {_key, schema} = OwnedState.Agent.state_spec([])

    stored = %Spec{
      module: OwnedState,
      options: [label: "stored"],
      state_key: :owned,
      state_schema: schema
    }

    assert {:error, %{message: "Plugin specs require an owner-facet manifest"}} =
             Plugin.normalize_all([stored])

    assert {:ok, [spec]} = Plugin.normalize_all([OwnedState])
    assert {:ok, [^spec]} = Plugin.normalize_all([spec])
  end

  test "manifest accessors retain owner order and restrict mapped options" do
    manifest = %Manifest{
      module: TopologyPackage,
      agent: EmptyAgentFacet,
      topology: TopologyFacet,
      option_keys: %{topology: [:result]}
    }

    assert Manifest.owners() == [:agent, :agent_server, :persistence, :topology]

    assert Enum.map(Manifest.owners(), &Manifest.facet(manifest, &1)) ==
             [EmptyAgentFacet, nil, nil, TopologyFacet]

    options = [result: {:error, :unavailable}]
    assert {:ok, ^manifest} = Manifest.validate(manifest, options)
    assert Manifest.options_for(manifest, :agent, options) == []
    assert Manifest.options_for(manifest, :topology, options) == options
    assert Manifest.options_for(%{manifest | option_keys: %{}}, :agent, options) == options
  end

  test "invalid manifest identities and versions return configuration errors" do
    manifest = %Manifest{module: TopologyPackage, topology: TopologyFacet}

    for {field, value, message} <- [
          {:module, nil, "Plugin package module is invalid"},
          {:module, "plugin", "Plugin package module is invalid"},
          {:vsn, 0, "Plugin package version must be positive"},
          {:vsn, "1", "Plugin package version must be positive"},
          {:topology, nil, "Plugin manifest must select at least one facet"},
          {:topology, "facet", "Plugin facet module is invalid"}
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
    manifest = %Manifest{module: TopologyPackage, topology: TopologyFacet}

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

  test "normalization reports mismatched package identity and missing facet capabilities" do
    assert {:error, %{details: %{plugin: MismatchedPackage, manifest: OwnedState}}} =
             Plugin.normalize_all([MismatchedPackage])

    for {package, facet, owner} <- [
          {EmptyAgentPackage, EmptyAgentFacet, :agent},
          {EmptyServerPackage, EmptyServerFacet, :agent_server}
        ] do
      assert {:error,
              %{
                message: "Plugin facet defines no capability",
                details: %{facet: ^facet, owner: ^owner}
              }} = Plugin.normalize_all([package])
    end

    assert {:error, %{message: "Agent Plugin reduce/2 requires state_spec/1"}} =
             Plugin.normalize_all([StatelessReducerPackage])

    assert {:error, %{details: %{facet: EmptyAgentFacet, owner: :persistence}}} =
             Plugin.normalize_all([WrongPersistencePackage])
  end

  test "facet metadata exceptions are contained at the normalization boundary" do
    assert {:error,
            %Jido.Error.ValidationError{
              message: "Plugin facet metadata failed",
              details: %{facet: RaisingMetadata, owner: :agent, error: %ArgumentError{}}
            }} = Plugin.normalize_all([RaisingMetadataPackage])

    assert {:error,
            %Jido.Error.ValidationError{
              message: "Plugin facet metadata failed",
              details: %{
                facet: ThrowingMetadata,
                owner: :agent,
                kind: :throw,
                reason: :facet_metadata_unavailable
              }
            }} = Plugin.normalize_all([ThrowingMetadataPackage])
  end

  test "Topology returns explicit errors and contains callback exceptions" do
    assert topology_result({:error, :unavailable}) == {:error, :unavailable}

    for result <- [:raise, :throw] do
      assert {:error, %Jido.Error.ExecutionError{details: details}} = topology_result(result)
      assert details.code == :plugin_callback_failed
      assert details.callback == :contribute
      assert details.plugin == TopologyPackage
      assert details.facet == TopologyFacet
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
      assert details.facet == TopologyFacet

      if result == :wrong_owner, do: assert(details.actual == OwnedState)
      if result == :invalid_shape, do: assert(%Jido.Error.ValidationError{} = details.reason)
    end
  end

  test "Topology contribution contexts enforce static identity fields" do
    {:ok, [spec]} = Plugin.normalize_all([TopologyPackage])
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
    {:ok, [spec]} = Plugin.normalize_all([{TopologyPackage, result: result}])
    context = TopologyPlugin.context(spec, "worker", __MODULE__)
    TopologyPlugin.contribute(spec, context)
  end
end

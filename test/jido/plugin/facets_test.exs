defmodule Jido.Plugin.FacetsTest do
  use ExUnit.Case, async: true

  alias Jido.Agent
  alias Jido.Persistence.Plugin, as: PersistencePlugin
  alias Jido.Plugin
  alias Jido.Plugin.DirectiveContext
  alias Jido.Signal
  alias Jido.Topology.Plugin, as: TopologyPlugin

  defmodule Effect do
    @moduledoc false
    defstruct [:label]
  end

  defmodule ForeignEffect do
    @moduledoc false
    defstruct [:label]
  end

  defmodule AgentFacet do
    @moduledoc false
    use Jido.Agent.Plugin

    def state_spec(_opts), do: {:facet_count, Zoi.integer() |> Zoi.default(7)}
    def directives(_opts), do: [Effect]
    def validate_directive(%Effect{} = directive, _opts), do: {:ok, directive}
    def update_state(state, _directives, _opts), do: {:ok, state + 1}
  end

  defmodule ServerFacet do
    @moduledoc false
    use Jido.AgentServer.Plugin

    def admit(_runtime, command, _opts), do: {:ok, command}

    def dispatch(_runtime, %Effect{label: label}, _context, opts) do
      if label == Keyword.fetch!(opts, :server_label), do: :ok, else: {:error, :wrong_label}
    end
  end

  defmodule PersistenceFacet do
    @moduledoc false
    use Jido.Persistence.Plugin

    def dump(value, _context, opts),
      do: {:ok, Keyword.fetch!(opts, :prefix) <> Integer.to_string(value)}

    def load(value, _context, opts) do
      prefix = Keyword.fetch!(opts, :prefix)
      {number, ""} = value |> String.replace_prefix(prefix, "") |> Integer.parse()
      {:ok, number}
    end
  end

  defmodule TopologyFacet do
    @moduledoc false
    use Jido.Topology.Plugin

    alias Jido.Topology.Plugin.Contribution, as: TopologyContribution

    def contribute(context, opts) do
      bus = Keyword.fetch!(opts, :bus)

      {:ok,
       %TopologyContribution{
         plugin: context.plugin,
         resources: [%{key: bus, config: []}],
         connections: [%{agent: context.agent_key, to: bus, path: "facet.**"}]
       }}
    end
  end

  defmodule Package do
    @moduledoc false
    use Jido.Plugin,
      agent: AgentFacet,
      agent_server: ServerFacet,
      persistence: PersistenceFacet,
      topology: TopologyFacet,
      vsn: 3,
      option_keys: [
        agent: [:agent_label],
        agent_server: [:server_label],
        persistence: [:prefix],
        topology: [:bus]
      ]
  end

  defmodule Record do
    @moduledoc false
    use Jido.Action, name: "plugin_facet_record"

    def run(_input, context) do
      state = %{context.agent_state | visible: context.agent_state.visible + 1, seen: "facet"}
      {:ok, state, [%Effect{label: "facet"}]}
    end
  end

  defmodule WrongOwnerPackage do
    @moduledoc false
    use Jido.Plugin, agent_server: AgentFacet
  end

  defmodule StatelessAgentFacet do
    @moduledoc false
    use Jido.Agent.Plugin
    def state_spec(_opts), do: :none
  end

  defmodule InvalidPersistencePackage do
    @moduledoc false
    use Jido.Plugin, agent: StatelessAgentFacet, persistence: PersistenceFacet
  end

  defmodule NonPortablePersistenceFacet do
    @moduledoc false
    use Jido.Persistence.Plugin

    def dump(_value, _context, _opts), do: {:ok, self()}
    def load(_value, _context, _opts), do: {:ok, self()}
  end

  defmodule InvalidLoadPersistenceFacet do
    @moduledoc false
    use Jido.Persistence.Plugin

    def dump(value, _context, _opts), do: {:ok, value}
    def load(_value, _context, _opts), do: {:ok, "not an integer"}
  end

  defmodule NonPortablePersistencePackage do
    @moduledoc false
    use Jido.Plugin, agent: AgentFacet, persistence: NonPortablePersistenceFacet
  end

  defmodule InvalidLoadPersistencePackage do
    @moduledoc false
    use Jido.Plugin, agent: AgentFacet, persistence: InvalidLoadPersistenceFacet
  end

  defmodule InvalidTopologyFacet do
    @moduledoc false
    use Jido.Topology.Plugin

    alias Jido.Topology.Plugin.Contribution, as: TopologyContribution

    def contribute(context, _opts) do
      {:ok,
       %TopologyContribution{
         plugin: context.plugin,
         resources: [%{key: "invalid", module: __MODULE__}]
       }}
    end
  end

  defmodule InvalidTopologyPackage do
    @moduledoc false
    use Jido.Plugin, topology: InvalidTopologyFacet
  end

  defmodule MisassignedOptionsPackage do
    @moduledoc false
    use Jido.Plugin, agent: StatelessAgentFacet, option_keys: [topology: [:bus]]
  end

  defmodule ReturnForeign do
    @moduledoc false
    use Jido.Action, name: "plugin_facet_return_foreign"

    def run(_input, context), do: {:ok, context.agent_state, [%ForeignEffect{label: "foreign"}]}
  end

  test "one manifest normalizes to four owner-specific Specs" do
    options = options()
    assert {:ok, [spec]} = Plugin.normalize_all([{Package, options}])

    assert spec.manifest.module == Package
    assert spec.manifest.vsn == 3
    assert spec.agent.module == AgentFacet
    assert spec.agent.options == [agent_label: "facet"]
    assert spec.agent_server.module == ServerFacet
    assert spec.agent_server.options == [server_label: "facet"]
    assert spec.persistence.module == PersistenceFacet
    assert spec.persistence.options == [prefix: "v3:"]
    assert spec.topology.module == TopologyFacet
    assert spec.topology.options == [bus: "facet_bus"]

    refute Map.has_key?(Map.from_struct(spec.agent), :runtime?)
    refute Map.has_key?(Map.from_struct(spec.agent_server), :state_schema)
    refute Map.has_key?(Map.from_struct(spec.persistence), :agent_server)
    refute Map.has_key?(Map.from_struct(spec.topology), :adapter)

    refute Jido.Plugin in Keyword.get_values(Package.module_info(:attributes), :behaviour)
    refute function_exported?(Package, :prepare, 2)
  end

  test "Agent facet updates only its owned state" do
    agent = agent()
    signal = Signal.new!("facet.run", %{}, source: "/test")

    assert {:ok, candidate, [%Effect{label: "facet"}]} = Agent.cmd(agent, signal)
    assert candidate.state.visible == 3
    assert candidate.state.seen == "facet"
    assert candidate.state.facet_count == 8
  end

  test "Server, Persistence, and Topology facets use only their owner values" do
    assert {:ok, [spec]} = Plugin.normalize_all([{Package, options()}])

    assert :ok =
             Jido.AgentServer.Plugin.dispatch(
               spec,
               nil,
               %Effect{label: "facet"},
               struct(DirectiveContext)
             )

    dump_context = PersistencePlugin.context(spec, :dump, 1, :test)
    assert {:ok, "v3:7"} = PersistencePlugin.dump(spec, 7, dump_context)

    load_context = PersistencePlugin.context(spec, :load, 1, :test)
    assert {:ok, 7} = PersistencePlugin.load(spec, "v3:7", load_context)

    topology_context = TopologyPlugin.context(spec, "worker", FacetAgent)
    assert {:ok, contribution} = TopologyPlugin.contribute(spec, topology_context)
    assert contribution.resources == [%{key: "facet_bus", config: []}]

    assert contribution.connections == [
             %{agent: "worker", to: "facet_bus", path: "facet.**"}
           ]
  end

  test "normalization rejects wrong owners and unpaired Persistence" do
    assert {:error, %Jido.Error.ValidationError{message: owner_message}} =
             Plugin.normalize_all([WrongOwnerPackage])

    assert owner_message == "Plugin facet must use its owner behavior"

    assert {:error, %Jido.Error.ValidationError{message: persistence_message}} =
             Plugin.normalize_all([InvalidPersistencePackage])

    assert persistence_message == "Persistence Plugin facet requires a stateful Agent facet"

    assert {:error, %Jido.Error.ValidationError{message: mapping_message}} =
             Plugin.normalize_all([MisassignedOptionsPackage])

    assert mapping_message == "Plugin option mapping names an unselected facet"
  end

  test "Persistence rejects foreign contexts, non-portable output, and invalid loaded state" do
    assert {:ok, [spec]} = Plugin.normalize_all([NonPortablePersistencePackage])
    dump_context = PersistencePlugin.context(spec, :dump, 1, :test)
    load_context = PersistencePlugin.context(spec, :load, 1, :test)

    assert {:error, %Jido.Error.ExecutionError{details: %{code: :non_portable_term}}} =
             PersistencePlugin.dump(spec, 7, dump_context)

    assert {:error, %Jido.Error.ExecutionError{details: %{code: :non_portable_term}}} =
             PersistencePlugin.load(spec, "7", load_context)

    assert {:error, %Jido.Error.ValidationError{message: context_message}} =
             PersistencePlugin.dump(spec, 7, %{dump_context | plugin: String})

    assert context_message == "Persistence Plugin context does not match its owner"

    assert {:ok, [invalid_load_spec]} = Plugin.normalize_all([InvalidLoadPersistencePackage])
    invalid_load_context = PersistencePlugin.context(invalid_load_spec, :load, 1, :test)

    assert {:error, %Jido.Error.ExecutionError{message: state_message}} =
             PersistencePlugin.load(invalid_load_spec, "7", invalid_load_context)

    assert state_message == "Persistence Plugin loaded invalid owned state"
  end

  test "Topology validates context ownership and each canonical entry" do
    assert {:ok, [spec]} = Plugin.normalize_all([InvalidTopologyPackage])
    context = TopologyPlugin.context(spec, "worker", FacetAgent)

    assert {:error, %Jido.Error.ValidationError{}} = TopologyPlugin.contribute(spec, context)

    assert {:error, %Jido.Error.ValidationError{message: message}} =
             TopologyPlugin.contribute(spec, %{context | plugin: String})

    assert message == "Topology Plugin context does not match its owner"
  end

  test "an executable cannot return a Directive without an owner" do
    agent =
      Agent.new!(
        name: "foreign_plugin_directive",
        schema: Zoi.object(%{count: Zoi.integer() |> Zoi.default(0)}),
        routes: [{"facet.foreign", ReturnForeign}]
      )
      |> Agent.instantiate!()

    signal = Signal.new!("facet.foreign", %{}, source: "/test")

    assert {:error, %Jido.Error.ValidationError{message: message}} = Agent.cmd(agent, signal)
    assert message == "Agent Directive has no owner"
  end

  defp agent do
    Agent.new!(
      name: "plugin_facets",
      schema:
        Zoi.object(%{
          visible: Zoi.integer() |> Zoi.default(2),
          seen: Zoi.string() |> Zoi.default("")
        }),
      plugins: [{Package, options()}],
      routes: [{"facet.run", Record}]
    )
    |> Agent.instantiate!()
  end

  defp options do
    [agent_label: "facet", server_label: "facet", prefix: "v3:", bus: "facet_bus"]
  end
end

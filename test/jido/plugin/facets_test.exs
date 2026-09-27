defmodule Jido.Plugin.FacetsTest do
  use ExUnit.Case, async: true

  alias Jido.Agent
  alias Jido.Persistence.Plugin, as: PersistencePlugin
  alias Jido.Plugin.DirectiveContext
  alias Jido.Signal
  alias Jido.Topology.Plugin, as: TopologyPlugin

  defmodule Effect do
    @moduledoc false
    use Jido.Agent.Directive
    defstruct [:label]

    @impl true
    def validate(%__MODULE__{label: label} = directive) when is_binary(label),
      do: {:ok, %{directive | label: "validated:" <> label}}

    def validate(_directive), do: {:error, :label_required}
  end

  defmodule ForeignEffect do
    @moduledoc false
    defstruct [:label]
  end

  defmodule SchemaEffect do
    @moduledoc false
    use Jido.Agent.Directive

    @schema Zoi.struct(__MODULE__, %{count: Zoi.integer()}, coerce: true)
    @enforce_keys Zoi.Struct.enforce_keys(@schema)
    defstruct Zoi.Struct.struct_fields(@schema)

    def schema, do: @schema
  end

  defmodule AgentFacet do
    @moduledoc false
    @behaviour Jido.Plugin

    alias Jido.Agent.Plugin.Reduction

    def prepare(%Jido.Agent.Plugin.Preparation{} = preparation, opts),
      do:
        {:ok,
         %{
           owned: preparation.plugin_state,
           state: preparation.agent_state,
           label: opts[:agent_label]
         }}

    def state_spec(_opts), do: {:facet_count, Zoi.integer() |> Zoi.default(7)}
    def directives(_opts), do: [Effect, SchemaEffect]
    def reduce(%Reduction{plugin_state: state}, _opts), do: {:ok, state + 1}
  end

  defmodule ServerFacet do
    @moduledoc false
    @behaviour Jido.Plugin

    alias Jido.AgentServer.Plugin.Admission

    def admit(_runtime, %Admission{} = admission, _opts) do
      {:ok,
       %{
         agent_id: admission.agent_id,
         agent_module: admission.agent_module,
         caller_context: admission.caller_context,
         plugin_state: admission.plugin_state,
         prepared_input: admission.prepared_input,
         signal_id: admission.signal.id,
         state_version: admission.state_version
       }}
    end

    def dispatch(_runtime, %Effect{label: label}, _context, opts) do
      if label == Keyword.fetch!(opts, :server_label), do: :ok, else: {:error, :wrong_label}
    end

    def dispatch(_runtime, %SchemaEffect{}, _context, _opts), do: :ok
  end

  defmodule PersistenceFacet do
    @moduledoc false
    @behaviour Jido.Plugin

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
    @behaviour Jido.Plugin

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
      vsn: 3,
      option_keys: [
        agent: [:agent_label],
        agent_server: [:server_label],
        persistence: [:prefix],
        topology: [:bus]
      ]

    @impl true
    defdelegate prepare(preparation, opts), to: Jido.Plugin.FacetsTest.AgentFacet

    @impl true
    defdelegate state_spec(opts), to: Jido.Plugin.FacetsTest.AgentFacet

    @impl true
    defdelegate directives(opts), to: Jido.Plugin.FacetsTest.AgentFacet

    @impl true
    defdelegate reduce(reduction, opts), to: Jido.Plugin.FacetsTest.AgentFacet

    @impl true
    defdelegate admit(runtime, admission, opts), to: Jido.Plugin.FacetsTest.ServerFacet

    @impl true
    defdelegate dispatch(runtime, directive, context, opts),
      to: Jido.Plugin.FacetsTest.ServerFacet

    @impl true
    defdelegate dump(value, context, opts), to: Jido.Plugin.FacetsTest.PersistenceFacet

    @impl true
    defdelegate load(value, context, opts), to: Jido.Plugin.FacetsTest.PersistenceFacet

    @impl true
    defdelegate contribute(context, opts), to: Jido.Plugin.FacetsTest.TopologyFacet
  end

  defmodule LocalPackage do
    use Jido.Plugin,
      vsn: 3,
      option_keys: [
        agent: [:agent_label],
        agent_server: [:server_label],
        persistence: [:prefix],
        topology: [:bus]
      ]

    defdelegate prepare(preparation, opts), to: AgentFacet
    defdelegate state_spec(opts), to: AgentFacet
    defdelegate directives(opts), to: AgentFacet
    defdelegate reduce(reduction, opts), to: AgentFacet
    defdelegate admit(runtime, admission, opts), to: ServerFacet
    defdelegate dispatch(runtime, directive, context, opts), to: ServerFacet
    defdelegate dump(value, context, opts), to: PersistenceFacet
    defdelegate load(value, context, opts), to: PersistenceFacet
    defdelegate contribute(context, opts), to: TopologyFacet
  end

  defmodule MixedPackage do
    use Jido.Plugin

    @impl true
    defdelegate admit(runtime, admission, opts), to: Jido.Plugin.FacetsTest.ServerFacet

    @impl true
    defdelegate dispatch(runtime, directive, context, opts),
      to: Jido.Plugin.FacetsTest.ServerFacet

    @impl true
    defdelegate prepare(preparation, opts), to: AgentFacet
    @impl true
    defdelegate state_spec(opts), to: AgentFacet
    @impl true
    defdelegate directives(opts), to: AgentFacet
    @impl true
    defdelegate reduce(reduction, opts), to: AgentFacet
  end

  defmodule Record do
    @moduledoc false
    use Jido.Action, name: "plugin_facet_record"

    def run(_input, context) do
      state = %{context.agent_state | visible: context.agent_state.visible + 1, seen: "facet"}
      {:ok, state, [%Effect{label: "facet"}]}
    end
  end

  defmodule PackageWithOwnedDumpCallback do
    @moduledoc false
    use Jido.Plugin

    @impl true
    defdelegate prepare(preparation, opts), to: Jido.Plugin.FacetsTest.AgentFacet

    @impl true
    defdelegate state_spec(opts), to: Jido.Plugin.FacetsTest.AgentFacet

    @impl true
    defdelegate directives(opts), to: Jido.Plugin.FacetsTest.AgentFacet

    @impl true
    defdelegate reduce(reduction, opts), to: Jido.Plugin.FacetsTest.AgentFacet
    @impl true
    def dump(value, _context, _opts), do: {:ok, value}
  end

  defmodule PackageWithOwnedLoadCallback do
    @moduledoc false
    use Jido.Plugin

    @impl true
    defdelegate prepare(preparation, opts), to: Jido.Plugin.FacetsTest.AgentFacet

    @impl true
    defdelegate state_spec(opts), to: Jido.Plugin.FacetsTest.AgentFacet

    @impl true
    defdelegate directives(opts), to: Jido.Plugin.FacetsTest.AgentFacet

    @impl true
    defdelegate reduce(reduction, opts), to: Jido.Plugin.FacetsTest.AgentFacet
    @impl true
    def load(value, _context, _opts), do: {:ok, value}
  end

  defmodule StatelessAgentFacet do
    @moduledoc false
    @behaviour Jido.Plugin
    def state_spec(_opts), do: :none
  end

  defmodule InvalidPersistencePackage do
    @moduledoc false
    use Jido.Plugin

    @impl true
    defdelegate state_spec(opts), to: Jido.Plugin.FacetsTest.StatelessAgentFacet

    @impl true
    defdelegate dump(value, context, opts), to: Jido.Plugin.FacetsTest.PersistenceFacet

    @impl true
    defdelegate load(value, context, opts), to: Jido.Plugin.FacetsTest.PersistenceFacet
  end

  defmodule NonPortablePersistenceFacet do
    @moduledoc false
    @behaviour Jido.Plugin

    def dump(_value, _context, _opts), do: {:ok, self()}
    def load(_value, _context, _opts), do: {:ok, self()}
  end

  defmodule InvalidLoadPersistenceFacet do
    @moduledoc false
    @behaviour Jido.Plugin

    def dump(value, _context, _opts), do: {:ok, value}
    def load(_value, _context, _opts), do: {:ok, "not an integer"}
  end

  defmodule NonPortablePersistencePackage do
    @moduledoc false
    use Jido.Plugin

    @impl true
    defdelegate prepare(preparation, opts), to: Jido.Plugin.FacetsTest.AgentFacet

    @impl true
    defdelegate state_spec(opts), to: Jido.Plugin.FacetsTest.AgentFacet

    @impl true
    defdelegate directives(opts), to: Jido.Plugin.FacetsTest.AgentFacet

    @impl true
    defdelegate reduce(reduction, opts), to: Jido.Plugin.FacetsTest.AgentFacet

    @impl true
    defdelegate dump(value, context, opts), to: Jido.Plugin.FacetsTest.NonPortablePersistenceFacet

    @impl true
    defdelegate load(value, context, opts), to: Jido.Plugin.FacetsTest.NonPortablePersistenceFacet
  end

  defmodule InvalidLoadPersistencePackage do
    @moduledoc false
    use Jido.Plugin

    @impl true
    defdelegate prepare(preparation, opts), to: Jido.Plugin.FacetsTest.AgentFacet

    @impl true
    defdelegate state_spec(opts), to: Jido.Plugin.FacetsTest.AgentFacet

    @impl true
    defdelegate directives(opts), to: Jido.Plugin.FacetsTest.AgentFacet

    @impl true
    defdelegate reduce(reduction, opts), to: Jido.Plugin.FacetsTest.AgentFacet

    @impl true
    defdelegate dump(value, context, opts), to: Jido.Plugin.FacetsTest.InvalidLoadPersistenceFacet

    @impl true
    defdelegate load(value, context, opts), to: Jido.Plugin.FacetsTest.InvalidLoadPersistenceFacet
  end

  defmodule InvalidTopologyFacet do
    @moduledoc false
    @behaviour Jido.Plugin

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
    use Jido.Plugin

    @impl true
    defdelegate contribute(context, opts), to: Jido.Plugin.FacetsTest.InvalidTopologyFacet
  end

  defmodule FacetWithPluginDirectiveValidation do
    @moduledoc false
    @behaviour Jido.Plugin

    def directives(_opts), do: [Effect]
    def validate_directive(directive, _opts), do: {:ok, directive}
  end

  defmodule PackageWithPluginDirectiveValidation do
    @moduledoc false
    use Jido.Plugin

    @impl true
    defdelegate directives(opts), to: Jido.Plugin.FacetsTest.FacetWithPluginDirectiveValidation

    defdelegate validate_directive(directive, opts),
      to: Jido.Plugin.FacetsTest.FacetWithPluginDirectiveValidation
  end

  defmodule FacetWithLegacyStateUpdate do
    @moduledoc false
    @behaviour Jido.Plugin

    def state_spec(_opts), do: {:legacy_state, Zoi.integer() |> Zoi.default(0)}
    def update_state(state, _directives, _opts), do: {:ok, state}
  end

  defmodule PackageWithLegacyStateUpdate do
    @moduledoc false
    use Jido.Plugin

    @impl true
    defdelegate state_spec(opts), to: Jido.Plugin.FacetsTest.FacetWithLegacyStateUpdate

    defdelegate update_state(state, directives, opts),
      to: Jido.Plugin.FacetsTest.FacetWithLegacyStateUpdate
  end

  defmodule FacetWithUnvalidatedDirective do
    @moduledoc false
    @behaviour Jido.Plugin

    def directives(_opts), do: [ForeignEffect]
  end

  defmodule PackageWithUnvalidatedDirective do
    @moduledoc false
    use Jido.Plugin

    @impl true
    defdelegate directives(opts), to: Jido.Plugin.FacetsTest.FacetWithUnvalidatedDirective
  end

  defmodule MisassignedOptionsPackage do
    @moduledoc false
    use Jido.Plugin, option_keys: [topology: [:bus]]

    @impl true
    defdelegate state_spec(opts), to: Jido.Plugin.FacetsTest.StatelessAgentFacet
  end

  defmodule ReturnForeign do
    @moduledoc false
    use Jido.Action, name: "plugin_facet_return_foreign"

    def run(_input, context), do: {:ok, context.agent_state, [%ForeignEffect{label: "foreign"}]}
  end

  test "callback delegation preserves owner Specs, options, version, and stored declarations" do
    assert {:ok, [separate]} = Jido.Plugin.Normalizer.normalize_all([{Package, options()}])
    assert {:ok, [local]} = Jido.Plugin.Normalizer.normalize_all([{LocalPackage, options()}])

    for owner <- Jido.Plugin.Manifest.owners() do
      assert Map.fetch!(local.manifest, owner) == LocalPackage
      local_spec = Map.fetch!(local, owner)
      separate_spec = Map.fetch!(separate, owner)
      assert local_spec.package == LocalPackage
      assert local_spec.module == LocalPackage

      assert %{local_spec | package: separate_spec.package, module: separate_spec.module} ==
               separate_spec
    end

    assert local.manifest.vsn == separate.manifest.vsn
    assert local.options == separate.options

    for package <- [Package, LocalPackage] do
      assert {:ok, document, registry} = Jido.Plugin.Codec.encode({package, options()})
      assert {:ok, {^package, decoded}} = Jido.Plugin.Codec.decode(document, registry)
      assert decoded == options()
      assert Map.keys(document) |> Enum.sort() == ~w(module options type version)
    end
  end

  test "Plugin callbacks can delegate to ordinary helpers" do
    assert {:ok, [spec]} = Jido.Plugin.Normalizer.normalize_all([MixedPackage])
    assert spec.agent.module == MixedPackage
    assert spec.agent_server.module == MixedPackage
    assert spec.manifest.module == MixedPackage
  end

  test "Plugins share state ownership checks" do
    assert {:error, %{message: "Plugin-owned Agent state keys must be unique"}} =
             Jido.Plugin.Normalizer.normalize_all([
               {Package, options()},
               {LocalPackage, options()}
             ])

    for package <- [Package, LocalPackage] do
      assert {:error, %{message: "Plugin-owned Agent state key conflicts with the domain schema"}} =
               Jido.Agent.new(
                 name: "conflict",
                 schema: Zoi.object(%{facet_count: Zoi.integer()}),
                 plugins: [{package, options()}]
               )
    end
  end

  test "one manifest normalizes to four owner-specific Specs" do
    options = options()
    assert {:ok, [spec]} = Jido.Plugin.Normalizer.normalize_all([{Package, options}])

    assert spec.manifest.module == Package
    assert spec.manifest.vsn == 3
    assert spec.agent.module == Package
    assert spec.agent.options == [agent_label: "facet"]
    assert spec.agent_server.module == Package
    assert spec.agent_server.options == [server_label: "validated:facet"]
    assert spec.persistence.module == Package
    assert spec.persistence.options == [prefix: "v3:"]
    assert spec.topology.module == Package
    assert spec.topology.options == [bus: "facet_bus"]

    refute Map.has_key?(Map.from_struct(spec.agent), :runtime?)
    refute Map.has_key?(Map.from_struct(spec.agent_server), :state_schema)
    refute Map.has_key?(Map.from_struct(spec.persistence), :agent_server)
    refute Map.has_key?(Map.from_struct(spec.topology), :adapter)

    assert Jido.Plugin in List.flatten(
             Keyword.get_values(Package.module_info(:attributes), :behaviour)
           )

    assert function_exported?(Package, :prepare, 2)
    refute function_exported?(AgentFacet, :validate_directive, 2)
    refute function_exported?(AgentFacet, :update_state, 3)
  end

  for package <- [Package, LocalPackage] do
    @package package
    test "#{inspect(@package)}: prepared input keeps its package identity and owner options" do
      agent = agent(@package)
      signal = Signal.new!("facet.run", %{}, source: "/test")
      assert {:ok, specs} = Jido.Plugin.Normalizer.normalize_all([{@package, options()}])
      assert {:ok, inputs} = Jido.Agent.Plugin.prepare(agent, signal, specs)

      assert inputs == %{
               @package => %Jido.Plugin.Input{
                 prepared: %{owned: 7, state: agent.state, label: "facet"}
               }
             }
    end

    test "#{inspect(@package)}: Agent facet validates each Directive once and reduces only its owned state" do
      agent = agent(@package)
      signal = Signal.new!("facet.run", %{}, source: "/test")

      assert {:ok, candidate, [%Effect{label: "validated:facet"}]} = Agent.cmd(agent, signal)
      assert candidate.state.visible == 3
      assert candidate.state.seen == "facet"
      assert candidate.state.facet_count == 8
    end

    test "#{inspect(@package)}: explicit Agent facets use reduce and Directive-owned validation" do
      assert {:ok, %SchemaEffect{count: 2}} =
               Jido.Agent.Directive.validate(%SchemaEffect{count: 2})

      assert {:error, _issues} = Jido.Agent.Directive.validate(%SchemaEffect{count: "2"})

      assert {:error, validation_error} =
               Jido.Plugin.Normalizer.normalize_all([PackageWithPluginDirectiveValidation])

      assert validation_error.message ==
               "Agent Plugin Directive validation belongs to the Directive module"

      assert {:error, reducer_error} =
               Jido.Plugin.Normalizer.normalize_all([PackageWithLegacyStateUpdate])

      assert reducer_error.message == "Agent Plugin state middleware must define reduce/2"

      assert {:error, directive_error} =
               Jido.Plugin.Normalizer.normalize_all([PackageWithUnvalidatedDirective])

      assert directive_error.message == "Agent Plugin Directive must define validate/1"
    end

    test "#{inspect(@package)}: Agent Server admission adds runtime input without replacing pure input or command data" do
      agent = agent(@package)
      signal = Signal.new!("facet.run", %{}, source: "/test")
      assert {:ok, [spec]} = Jido.Plugin.Normalizer.normalize_all([{@package, options()}])
      assert {:ok, command} = Jido.Agent.Command.new(agent, signal, %{request: "one"})

      prepared = %Jido.Plugin.Input{prepared: %{tenant: "alpha"}}
      command = %{command | plugin_inputs: %{@package => prepared}}

      assert {:ok, admitted} =
               Jido.AgentServer.Plugin.Callbacks.admit(
                 command,
                 [spec],
                 %{@package => :runtime},
                 12
               )

      assert admitted.agent === command.agent
      assert admitted.signal === command.signal
      assert admitted.context === command.context

      assert admitted.plugin_inputs[@package] == %Jido.Plugin.Input{
               prepared: %{tenant: "alpha"},
               runtime: %{
                 agent_id: agent.id,
                 agent_module: agent.module,
                 caller_context: %{request: "one"},
                 plugin_state: 7,
                 prepared_input: %{tenant: "alpha"},
                 signal_id: signal.id,
                 state_version: 12
               }
             }
    end

    test "#{inspect(@package)}: Server, Persistence, and Topology facets use only their owner values" do
      assert {:ok, [spec]} = Jido.Plugin.Normalizer.normalize_all([{@package, options()}])

      assert :ok =
               Jido.AgentServer.Plugin.Callbacks.dispatch(
                 spec,
                 nil,
                 %Effect{label: "validated:facet"},
                 struct(DirectiveContext)
               )

      dump_context = PersistencePlugin.context(spec, :dump, 1, :test)
      assert {:ok, "v3:7"} = PersistencePlugin.dump(spec, 7, dump_context)

      load_context = PersistencePlugin.context(spec, :load, 1, :test)
      assert {:ok, 7} = PersistencePlugin.load(spec, "v3:7", load_context)

      topology_context = TopologyPlugin.context(spec, "worker", FacetAgent)
      assert {:ok, contribution} = TopologyPlugin.contribute(spec, topology_context)
      assert contribution.resources == [%{key: "facet_bus", kind: :bus, config: []}]

      assert contribution.connections == [
               %{agent: "worker", to: "facet_bus", path: "facet.**"}
             ]
    end
  end

  test "normalization rejects unpaired Persistence and unused option mappings" do
    assert {:error, %Jido.Error.ValidationError{message: persistence_message}} =
             Jido.Plugin.Normalizer.normalize_all([InvalidPersistencePackage])

    assert persistence_message == "Persistence Plugin facet requires a stateful Agent facet"

    assert {:error, %Jido.Error.ValidationError{message: mapping_message}} =
             Jido.Plugin.Normalizer.normalize_all([MisassignedOptionsPackage])

    assert mapping_message == "Plugin option mapping names an unselected facet"
  end

  test "Persistence requires both conversion callbacks" do
    for package <- [PackageWithOwnedDumpCallback, PackageWithOwnedLoadCallback] do
      assert {:error, %Jido.Error.ValidationError{message: message}} =
               Jido.Plugin.Normalizer.normalize_all([package])

      assert message == "Persistence Plugin facet must define dump/3 and load/3"
    end
  end

  test "Persistence rejects foreign contexts, non-portable output, and invalid loaded state" do
    assert {:ok, [spec]} = Jido.Plugin.Normalizer.normalize_all([NonPortablePersistencePackage])
    dump_context = PersistencePlugin.context(spec, :dump, 1, :test)
    load_context = PersistencePlugin.context(spec, :load, 1, :test)

    assert {:error, %Jido.Error.ExecutionError{details: %{code: :non_portable_term}}} =
             PersistencePlugin.dump(spec, 7, dump_context)

    assert {:error, %Jido.Error.ExecutionError{details: %{code: :non_portable_term}}} =
             PersistencePlugin.load(spec, "7", load_context)

    assert {:error, %Jido.Error.ValidationError{message: context_message}} =
             PersistencePlugin.dump(spec, 7, %{dump_context | plugin: String})

    assert context_message == "Persistence Plugin context does not match its owner"

    assert {:ok, [invalid_load_spec]} =
             Jido.Plugin.Normalizer.normalize_all([InvalidLoadPersistencePackage])

    invalid_load_context = PersistencePlugin.context(invalid_load_spec, :load, 1, :test)

    assert {:error, %Jido.Error.ExecutionError{message: state_message}} =
             PersistencePlugin.load(invalid_load_spec, "7", invalid_load_context)

    assert state_message == "Persistence Plugin loaded invalid owned state"
  end

  test "Topology validates context ownership and each canonical entry" do
    assert {:ok, [spec]} = Jido.Plugin.Normalizer.normalize_all([InvalidTopologyPackage])
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

  defp agent(package) do
    Agent.new!(
      name: "plugin_facets",
      schema:
        Zoi.object(%{
          visible: Zoi.integer() |> Zoi.default(2),
          seen: Zoi.string() |> Zoi.default("")
        }),
      plugins: [{package, options()}],
      routes: [{"facet.run", Record}]
    )
    |> Agent.instantiate!()
  end

  defp options do
    [
      agent_label: "facet",
      server_label: "validated:facet",
      prefix: "v3:",
      bus: "facet_bus"
    ]
  end
end

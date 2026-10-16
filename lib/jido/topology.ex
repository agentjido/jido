defmodule Jido.Topology do
  @moduledoc """
  A declarative definition of Agents, groups, resources, and logical ownership.

  Module declarations, data definitions, and `Jido.Topology.Codec` use
  the same constructor. Declaration and planning start no processes. Instance
  input is validated separately from Agent state. See the topology examples in
  `examples/07_topology` for startup, control Signals, placement, and JSON
  transport.

  Use `define/1` for static data definitions and `instantiate/2` for planned
  instances. Generated modules expose `instantiate/1` for a Topology instance
  and `instantiate_agent/1` for their owner Agent. Each constructor has a
  matching bang form. Existing `new` and `new_agent` functions remain
  compatibility wrappers with their original meanings and arities.

  A module can contain three root blocks. `agent` defines an optional control
  Agent. `routes` uses the normal Agent DSL and requires `agent`. `topology`
  contains all topology-specific sections. The control Agent and topology are
  independent authoring values. The generated `child_spec/1` starts them through
  `Jido.Topology.Runtime`, which owns the combined supervision tree.

  Pass static authoring extensions with
  `use Jido.Topology, extensions: [MyExtension]`. An extension can implement
  `Jido.Agent.Extension`, `Jido.Topology.Extension`, or both. The combined host
  sends its declarations to `lower_agent/2`, `lower_topology/2`, or both before
  common validation.

  An Agent or group selects exactly one `module:` or `definition:` source.
  A neutral definition retains its schema, routes, metadata, and Plugins.
  Planning checks resolved state before activation. The Topology Codec uses
  version 3 for neutral members and runtime children; module-only documents
  retain version 2.

  `children:` entries start separate runtimes through declared command and
  event gates. Static `include` composes one plan and cannot contain runtime
  children. See `Jido.Topology.Runtime` and the topology API review examples.

  During instance planning, each Agent or group declaration can add pure
  static entries through a declared `Jido.Topology.Plugin` facet. Jido adds
  Agent contributions, then group contributions, in Plugin declaration order.
  Included Topologies receive the same expansion in their own scope. The
  source definition stays unchanged, and common validation checks the complete
  plan before activation.

  Use `Jido.Topology.View` to combine an accepted instance and one status
  snapshot into bounded JSON data for an application UI or API.
  """

  alias Jido.Agent.Authoring
  alias Jido.Topology.{Composition, Instance, Plan, Plugin, Validation}

  @schema Zoi.struct(
            __MODULE__,
            %{
              name: Zoi.string(),
              schema: Zoi.any(),
              metadata: Zoi.map(),
              agents: Zoi.list(Zoi.map()),
              groups: Zoi.list(Zoi.map()),
              resources: Zoi.list(Zoi.map()),
              relationships: Zoi.list(Zoi.map()),
              connections: Zoi.list(Zoi.map()),
              includes: Zoi.list(Zoi.map()),
              children: Zoi.list(Zoi.map()),
              imports: Zoi.list(Zoi.map()),
              exports: Zoi.list(Zoi.map()),
              startup: Zoi.map()
            },
            coerce: true
          )
  @type t :: unquote(Zoi.type_spec(@schema))
  @enforce_keys Zoi.Struct.enforce_keys(@schema)
  defstruct Zoi.Struct.struct_fields(@schema)

  @doc "Returns the schema for a topology definition."
  def schema, do: @schema

  @doc "Declares a topology module."
  defmacro __using__(opts) do
    quote location: :keep do
      use Jido.Agent.Authoring.Compiler,
        host: :topology,
        agent_options: unquote(opts)

      import Jido.Topology.Reference, only: [input: 1, member: 1]
      import Jido.Topology.Ref, only: [ref: 2]

      @doc "Returns the topology owner Agent definition."
      @spec owner() :: Jido.Agent.definition()
      def owner, do: definition()

      @doc "Constructs the topology owner Agent."
      @spec instantiate_agent(map() | keyword()) ::
              {:ok, Jido.Agent.instance()} | {:error, Exception.t()}
      def instantiate_agent(opts \\ []) do
        Jido.Agent.instantiate(__MODULE__, opts)
      end

      @doc "Constructs the topology owner Agent or raises its validation error."
      @spec instantiate_agent!(map() | keyword()) :: Jido.Agent.instance() | no_return()
      def instantiate_agent!(opts \\ []) do
        Jido.Agent.instantiate!(__MODULE__, opts)
      end

      @doc "Compatibility wrapper for instantiate_agent/1."
      @spec new_agent(map() | keyword()) ::
              {:ok, Jido.Agent.instance()} | {:error, Exception.t()}
      def new_agent(opts \\ []), do: instantiate_agent(opts)

      @doc "Compatibility wrapper for instantiate_agent!/1."
      @spec new_agent!(map() | keyword()) :: Jido.Agent.instance() | no_return()
      def new_agent!(opts \\ []), do: instantiate_agent!(opts)

      @doc "Returns the topology definition."
      def topology, do: Jido.Topology.define!(__topology_config__())

      @doc "Constructs a topology instance without starting processes."
      @spec instantiate(map() | keyword()) ::
              {:ok, Jido.Topology.Instance.t()} | {:error, Exception.t()}
      def instantiate(opts), do: Jido.Topology.instantiate(__topology_config__(), opts)

      @doc "Constructs an instance or raises its validation error."
      @spec instantiate!(map() | keyword()) :: Jido.Topology.Instance.t() | no_return()
      def instantiate!(opts), do: Jido.Topology.instantiate!(__topology_config__(), opts)

      @doc "Compatibility wrapper for instantiate/1."
      @spec new(map() | keyword()) ::
              {:ok, Jido.Topology.Instance.t()} | {:error, Exception.t()}
      def new(opts), do: instantiate(opts)

      @doc "Compatibility wrapper for instantiate!/1."
      @spec new!(map() | keyword()) :: Jido.Topology.Instance.t() | no_return()
      def new!(opts), do: instantiate!(opts)

      @doc "Starts the topology runtime through an application supervisor."
      def child_spec(opts),
        do: Jido.Topology.Runtime.child_spec(Keyword.put(opts, :topology, __MODULE__))
    end
  end

  @doc "Validates static authoring data."
  @spec define(map() | keyword() | t()) :: {:ok, t()} | {:error, Exception.t()}
  def define(attrs) do
    with {:ok, definition, _composed, _resolved} <- define_with_composition(attrs),
         do: {:ok, definition}
  end

  defp define_with_composition(attrs) do
    with {:ok, definition, resolved} <- Validation.resolve(attrs, %{}),
         {:ok, composed} <- Composition.flatten(definition),
         :ok <- Jido.Topology.Child.validate(definition),
         do: {:ok, definition, composed, resolved}
  end

  @doc "Validates a definition or raises its error."
  @spec define!(map() | keyword() | t()) :: t() | no_return()
  def define!(attrs), do: unwrap!(define(attrs))

  @doc "Compatibility wrapper for define/1."
  @spec new(map() | keyword() | t()) :: {:ok, t()} | {:error, Exception.t()}
  def new(attrs), do: define(attrs)

  @doc "Compatibility wrapper for define!/1."
  @spec new!(map() | keyword() | t()) :: t() | no_return()
  def new!(attrs), do: define!(attrs)

  @doc "Validates input, applies static Plugin contributions, and builds an execution plan."
  @spec instantiate(t() | map() | keyword(), map() | keyword()) ::
          {:ok, Instance.t()} | {:error, Exception.t()}
  def instantiate(definition, opts) do
    with {:ok, definition, static_composed, resolved} <- define_with_composition(definition),
         {:ok, planning_definition, changed?} <- Plugin.expand_with_changes(definition, resolved),
         {:ok, composed} <- composition(planning_definition, changed?, static_composed),
         {:ok, opts} <- Authoring.attrs(opts),
         :ok <- Authoring.keys(opts, [:id, :input]),
         {:ok, id} <- Validation.key(Map.get(opts, :id)),
         {:ok, input} <- Validation.parse_input(definition.schema, Map.get(opts, :input, %{})),
         {:ok, plan} <- Plan.expand(planning_definition, id, input, composed, resolved),
         :ok <- Jido.Topology.Child.plan(definition, id, input, plan) do
      {:ok, %Instance{id: id, definition: definition, input: input, plan: plan}}
    end
  end

  @doc "Constructs a Topology instance or raises its validation error."
  @spec instantiate!(t() | map() | keyword(), map() | keyword()) :: Instance.t() | no_return()
  def instantiate!(definition, opts), do: unwrap!(instantiate(definition, opts))

  defp composition(_definition, false, composed), do: {:ok, composed}

  defp composition(definition, true, _composed), do: Composition.flatten(definition)

  @doc false
  defdelegate unwrap!(result), to: Authoring
end

defmodule Jido.Topology do
  @moduledoc """
  A declarative definition of Agents, groups, Buses, and logical ownership.

  Module declarations, `Jido.Topology.Builder`, and `Jido.Topology.Codec` use
  the same constructor. Declaration and planning start no processes. Instance
  input is validated separately from Agent state. See the topology examples in
  `examples/07_topology` for local startup and JSON transport.

  Pass static authoring extensions with
  `use Jido.Topology, extensions: [MyExtension]`. An extension can implement
  `Jido.Agent.Extension`, `Jido.Topology.Extension`, or both. The combined host
  sends its declarations to `lower_agent/2`, `lower_topology/2`, or both before
  common validation.

  During instance planning, each Agent or group declaration can add pure
  static entries through a declared `Jido.Topology.Plugin` facet. Jido adds
  Agent contributions, then group contributions, in Plugin declaration order.
  Included Topologies receive the same expansion in their own scope. The
  source definition stays unchanged, and common validation checks the complete
  plan before activation.
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
      use Jido.Agent.Definition,
        dsl: Jido.Topology.DSL,
        agent_options: unquote(opts),
        constructors?: false,
        combined_extensions?: true

      import Jido.Topology.Reference, only: [input: 1, member: 1]
      import Jido.Topology.Ref, only: [ref: 2]
      @topology_options unquote(opts)
      @before_compile Jido.Topology.DSL.Compiler

      @doc "Returns the topology owner Agent definition."
      @spec owner() :: Jido.Agent.definition()
      def owner, do: definition()

      @doc "Constructs the topology owner Agent."
      @spec new_agent(map() | keyword()) ::
              {:ok, Jido.Agent.instance()} | {:error, Exception.t()}
      def new_agent(opts \\ []) do
        Jido.Agent.instantiate(__MODULE__, opts)
      end

      @doc "Constructs the topology owner Agent or raises its validation error."
      @spec new_agent!(map() | keyword()) :: Jido.Agent.instance() | no_return()
      def new_agent!(opts \\ []) do
        Jido.Agent.instantiate!(__MODULE__, opts)
      end

      @doc "Returns the topology definition."
      def topology, do: Jido.Topology.new!(__topology_config__())

      @doc "Constructs a topology instance without starting processes."
      def new(opts), do: Jido.Topology.instantiate(topology(), opts)

      @doc "Constructs an instance or raises its validation error."
      def new!(opts), do: Jido.Topology.unwrap!(new(opts))
    end
  end

  @doc "Validates static authoring data."
  @spec new(map() | keyword() | t()) :: {:ok, t()} | {:error, Exception.t()}
  def new(attrs) do
    with {:ok, definition, _composed} <- new_with_composition(attrs), do: {:ok, definition}
  end

  defp new_with_composition(attrs) do
    with {:ok, attrs} <- Validation.definition(attrs),
         {:ok, composed} <- Composition.flatten(attrs),
         {:ok, definition} <- Zoi.parse(@schema, attrs),
         do: {:ok, definition, composed}
  end

  @doc "Validates a definition or raises its error."
  def new!(attrs), do: unwrap!(new(attrs))

  @doc "Validates input, applies static Plugin contributions, and builds a local plan."
  @spec instantiate(t(), map() | keyword()) :: {:ok, Instance.t()} | {:error, Exception.t()}
  def instantiate(definition, opts) do
    with {:ok, definition, _static_composed} <- new_with_composition(definition),
         {:ok, planning_definition} <- Plugin.expand_definition(definition),
         {:ok, composed} <- Composition.flatten(planning_definition),
         {:ok, opts} <- Authoring.attrs(opts),
         :ok <- Authoring.keys(opts, [:id, :input]),
         {:ok, id} <- Validation.key(Map.get(opts, :id)),
         {:ok, input} <- Validation.parse_input(definition.schema, Map.get(opts, :input, %{})),
         {:ok, plan} <- Plan.build_composed(planning_definition, id, input, composed) do
      {:ok, %Instance{id: id, definition: definition, input: input, plan: plan}}
    end
  end

  @doc false
  def unwrap!({:ok, value}), do: value
  def unwrap!({:error, error}), do: raise(error)
end

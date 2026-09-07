defmodule Jido.Topology do
  @moduledoc """
  A declarative definition of Agents, groups, Buses, and logical ownership.

  Module declarations, `Jido.Topology.Builder`, and `Jido.Topology.Codec` use
  the same constructor. Declaration and planning start no processes. Instance
  input is validated separately from Agent state. See the topology examples in
  `examples/07_topology` for local startup and JSON transport.

  Pass static authoring extensions with
  `use Jido.Topology, extensions: [MyExtension]`. Each extension implements
  `Jido.Topology.Extension` and lowers its declarations into ordinary Topology
  configuration before common validation.
  """

  alias Jido.Agent.Authoring
  alias Jido.Topology.{Composition, Instance, Plan, Validation}

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
    {owner_opts, topology_opts} =
      if is_list(opts) do
        {
          Keyword.take(opts, [:name, :description, :max_state_size, :extensions]),
          Keyword.drop(opts, [:description, :max_state_size])
        }
      else
        {opts, opts}
      end

    owner_opts =
      if is_list(owner_opts) do
        Keyword.put(owner_opts, :__host__, :topology)
      else
        owner_opts
      end

    quote location: :keep do
      use Jido.Agent, unquote(owner_opts)
      import Jido.Topology.Reference, only: [input: 1, member: 1]
      import Jido.Topology.Ref, only: [ref: 2]
      @topology_options unquote(topology_opts)
      @before_compile Jido.Topology.DSL.Compiler

      @doc "Returns the topology owner Agent definition."
      @spec owner() :: Jido.Agent.t()
      def owner, do: agent()

      @doc "Constructs the topology owner Agent."
      @spec new_agent(map() | keyword()) ::
              {:ok, Jido.Agent.t()} | {:error, Exception.t()}
      def new_agent(opts \\ []) do
        Jido.Agent.new(__MODULE__, opts)
      end

      @doc "Constructs the topology owner Agent or raises its validation error."
      @spec new_agent!(map() | keyword()) :: Jido.Agent.t() | no_return()
      def new_agent!(opts \\ []) do
        Jido.Agent.new!(__MODULE__, opts)
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

  @doc "Validates instance input and builds a stable local execution plan."
  @spec instantiate(t(), map() | keyword()) :: {:ok, Instance.t()} | {:error, Exception.t()}
  def instantiate(definition, opts) do
    with {:ok, definition, composed} <- new_with_composition(definition),
         {:ok, opts} <- Authoring.attrs(opts),
         :ok <- Authoring.keys(opts, [:id, :input]),
         {:ok, id} <- Validation.key(Map.get(opts, :id)),
         {:ok, input} <- Validation.parse_input(definition.schema, Map.get(opts, :input, %{})),
         {:ok, plan} <- Plan.build_composed(definition, id, input, composed) do
      {:ok, %Instance{id: id, definition: definition, input: input, plan: plan}}
    end
  end

  @doc false
  def unwrap!({:ok, value}), do: value
  def unwrap!({:error, error}), do: raise(error)
end

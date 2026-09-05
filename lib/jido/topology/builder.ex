defmodule Jido.Topology.Builder do
  @moduledoc "Builds ordered topology declarations and preserves the first error."
  alias Jido.Agent.Authoring
  alias Jido.Topology
  alias Jido.Topology.Validation

  @schema Zoi.struct(__MODULE__, %{config: Zoi.map(), error: Zoi.any() |> Zoi.nullable()})
  @type t :: unquote(Zoi.type_spec(@schema))
  @enforce_keys Zoi.Struct.enforce_keys(@schema)
  defstruct Zoi.Struct.struct_fields(@schema)

  @doc "Returns the Builder schema."
  def schema, do: @schema

  @doc "Starts from authoring fields, a definition, or a topology module."
  def new(%Topology{} = value), do: new(Map.from_struct(value))

  def new(module) when is_atom(module) do
    if Code.ensure_loaded?(module) and function_exported?(module, :__topology_config__, 0) do
      new(module.__topology_config__())
    else
      {:error, error} = Authoring.error("Expected a topology module")
      %__MODULE__{config: %{}, error: error}
    end
  end

  def new(attrs) do
    with {:ok, config} <- Authoring.attrs(attrs), :ok <- Validation.keys(config) do
      Enum.reduce(config, %__MODULE__{config: %{}, error: nil}, fn {key, value}, builder ->
        put(builder, key, value)
      end)
    else
      {:error, error} -> %__MODULE__{config: %{}, error: error}
    end
  end

  @doc "Sets the topology name."
  def name(builder, value), do: put(builder, :name, value)

  @doc "Sets the input schema."
  def schema(builder, value), do: put(builder, :schema, value)
  @doc "Sets the metadata map."
  def metadata(builder, value), do: put(builder, :metadata, value)
  @doc "Sets the startup policy."
  def startup(builder, opts), do: set_entry(builder, :startup, opts)

  @doc "Appends one Agent."
  def agent(builder, key, module, opts \\ []),
    do: append(builder, :agent, %{key: key, module: module}, opts)

  @doc "Appends a counted or keyed Agent group."
  def group(builder, key, module, opts \\ []),
    do: append(builder, :group, %{key: key, module: module}, opts)

  @doc "Appends one Bus resource."
  def bus(builder, key, opts \\ []), do: append(builder, :bus, %{key: key}, opts)
  @doc "Declares logical ownership."
  def owns(builder, parent, child, opts \\ []),
    do: append(builder, :owns, %{parent: parent, child: child}, opts)

  @doc "Declares a normal Bus subscription for an Agent or group."
  def subscribe(builder, agent, opts), do: append(builder, :subscribe, %{agent: agent}, opts)

  @doc "Includes a topology under a stable component key. Options are inputs and bindings."
  def include(builder, key, topology, opts \\ []),
    do: append(builder, :include, %{key: key, topology: topology}, opts)

  @doc "Declares a required external Bus."
  def import_bus(builder, key), do: append(builder, :import, %{key: key, kind: :bus}, [])

  @doc "Exports one Agent, group, or Bus under a public name."
  def export(builder, kind, key, opts),
    do: append(builder, :export, %{kind: kind, key: key}, opts)

  @doc "Builds a validated definition."
  def build(%__MODULE__{error: error}) when not is_nil(error), do: {:error, error}
  def build(%__MODULE__{config: config}), do: Topology.new(config)
  @doc "Builds an instance with explicit options."
  def build(builder, opts) do
    with {:ok, definition} <- build(builder), do: Topology.instantiate(definition, opts)
  end

  @doc "Builds a definition or raises its error."
  def build!(builder), do: Topology.unwrap!(build(builder))
  @doc "Builds an instance or raises its error."
  def build!(builder, opts), do: Topology.unwrap!(build(builder, opts))

  defp append(%{error: error} = builder, _, _, _) when not is_nil(error), do: builder

  defp append(builder, kind, base, opts) do
    with {:ok, opts} <- Authoring.attrs(opts),
         :ok <- Authoring.keys(opts, Map.keys(opts) -- Map.keys(base)),
         {:ok, entry} <- Validation.entry(kind, Map.merge(base, opts)),
         field = collection(kind),
         {:ok, existing} <- Authoring.traverse(Map.get(builder.config, field, []), &{:ok, &1}) do
      put(builder, field, existing ++ [entry])
    else
      {:error, error} -> %{builder | error: error}
    end
  end

  defp set_entry(%{error: error} = builder, _, _) when not is_nil(error), do: builder

  defp set_entry(builder, kind, value) do
    case Validation.entry(kind, value) do
      {:ok, value} -> put(builder, kind, value)
      {:error, error} -> %{builder | error: error}
    end
  end

  defp put(%{error: error} = builder, _, _) when not is_nil(error), do: builder

  defp put(builder, key, value) do
    case Validation.field(key, value) do
      :ok -> %{builder | config: Map.put(builder.config, key, value)}
      {:error, error} -> %{builder | error: error}
    end
  end

  defp collection(:agent), do: :agents
  defp collection(:group), do: :groups
  defp collection(:bus), do: :resources
  defp collection(:owns), do: :relationships
  defp collection(:subscribe), do: :connections
  defp collection(:include), do: :includes
  defp collection(:import), do: :imports
  defp collection(:export), do: :exports
end

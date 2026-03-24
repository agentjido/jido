defmodule Jido.Pod.Topology do
  @moduledoc """
  Canonical pod topology data structure.

  Topologies are pure data. They define the named durable nodes that a pod
  manages and can be validated, stored, and mutated independently of runtime
  process state.
  """

  alias Jido.Pod.Topology.Node

  @topology_name_regex ~r/^[a-zA-Z][a-zA-Z0-9_]*$/

  @schema Zoi.struct(
            __MODULE__,
            %{
              name:
                Zoi.string(description: "The topology name.")
                |> Zoi.refine({__MODULE__, :validate_topology_name, []}),
              nodes:
                Zoi.map(description: "Named node definitions within the topology.")
                |> Zoi.default(%{}),
              links:
                Zoi.list(Zoi.any(), description: "Optional topology metadata.")
                |> Zoi.default([]),
              defaults:
                Zoi.map(description: "Optional topology defaults.")
                |> Zoi.default(%{}),
              version:
                Zoi.integer(description: "Topology version.")
                |> Zoi.min(1)
                |> Zoi.default(1)
            },
            coerce: true
          )

  @type t :: unquote(Zoi.type_spec(@schema))

  @enforce_keys Zoi.Struct.enforce_keys(@schema)
  defstruct Zoi.Struct.struct_fields(@schema)

  @doc false
  @spec schema() :: Zoi.schema()
  def schema, do: @schema

  @doc """
  Builds a validated topology.
  """
  @spec new(keyword() | map() | t()) :: {:ok, t()} | {:error, term()}
  def new(%__MODULE__{} = topology), do: {:ok, topology}

  def new(attrs) when is_list(attrs) do
    new(Map.new(attrs))
  end

  def new(attrs) when is_map(attrs) do
    with {:ok, name} <- normalize_name(Map.get(attrs, :name)),
         {:ok, nodes} <- normalize_nodes(Map.get(attrs, :nodes, %{})),
         {:ok, defaults} <- normalize_defaults(Map.get(attrs, :defaults, %{})),
         {:ok, links} <- normalize_links(Map.get(attrs, :links, [])) do
      attrs =
        attrs
        |> Map.put(:name, name)
        |> Map.put(:nodes, nodes)
        |> Map.put(:defaults, defaults)
        |> Map.put(:links, links)
        |> Map.put_new(:version, 1)

      Zoi.parse(@schema, attrs)
    end
  end

  def new(_attrs) do
    {:error,
     Jido.Error.validation_error(
       "Jido.Pod.Topology expects a keyword list, map, or topology struct."
     )}
  end

  @doc """
  Builds a validated topology, raising on error.
  """
  @spec new!(keyword() | map() | t()) :: t()
  def new!(attrs) do
    case new(attrs) do
      {:ok, topology} ->
        topology

      {:error, reason} ->
        raise Jido.Error.validation_error("Invalid pod topology", details: reason)
    end
  end

  @doc """
  Builds a topology from the common shorthand node map form.
  """
  @spec from_nodes(String.t(), map(), keyword()) :: {:ok, t()} | {:error, term()}
  def from_nodes(name, nodes, opts \\ []) when is_binary(name) and is_map(nodes) do
    opts
    |> Keyword.put(:name, name)
    |> Keyword.put(:nodes, nodes)
    |> new()
  end

  @doc """
  Builds a topology from shorthand, raising on error.
  """
  @spec from_nodes!(String.t(), map(), keyword()) :: t()
  def from_nodes!(name, nodes, opts \\ []) do
    case from_nodes(name, nodes, opts) do
      {:ok, topology} ->
        topology

      {:error, reason} ->
        raise Jido.Error.validation_error("Invalid pod topology", details: reason)
    end
  end

  @doc """
  Returns a copy of the topology with a new validated name.
  """
  @spec with_name(t(), String.t()) :: {:ok, t()} | {:error, term()}
  def with_name(%__MODULE__{} = topology, name) when is_binary(name) do
    case normalize_name(name) do
      {:ok, valid_name} -> {:ok, %{topology | name: valid_name}}
      {:error, _reason} = error -> error
    end
  end

  @doc """
  Inserts or replaces a node definition in the topology.
  """
  @spec put_node(t(), atom(), Node.t() | keyword() | map()) :: {:ok, t()} | {:error, term()}
  def put_node(%__MODULE__{} = topology, name, %Node{} = node) when is_atom(name) do
    {:ok, %{topology | nodes: Map.put(topology.nodes, name, %{node | name: name})}}
  end

  def put_node(%__MODULE__{} = topology, name, attrs) when is_atom(name) do
    case Node.new(name, attrs) do
      {:ok, node} -> {:ok, %{topology | nodes: Map.put(topology.nodes, name, node)}}
      {:error, _reason} = error -> error
    end
  end

  @doc """
  Removes a node from the topology.
  """
  @spec delete_node(t(), atom()) :: t()
  def delete_node(%__MODULE__{} = topology, name) when is_atom(name) do
    %{topology | nodes: Map.delete(topology.nodes, name)}
  end

  @doc """
  Fetches a node by name.
  """
  @spec fetch_node(t(), atom()) :: {:ok, Node.t()} | :error
  def fetch_node(%__MODULE__{} = topology, name) when is_atom(name) do
    Map.fetch(topology.nodes, name)
  end

  @doc """
  Appends a link to the topology if it is not already present.
  """
  @spec put_link(t(), term()) :: t()
  def put_link(%__MODULE__{} = topology, link) do
    if link in topology.links do
      topology
    else
      %{topology | links: topology.links ++ [link]}
    end
  end

  @doc """
  Removes a link from the topology.
  """
  @spec delete_link(t(), term()) :: t()
  def delete_link(%__MODULE__{} = topology, link) do
    %{topology | links: Enum.reject(topology.links, &(&1 == link))}
  end

  @doc false
  @spec validate_topology_name(String.t(), keyword()) :: :ok | {:error, String.t()}
  def validate_topology_name(name, _opts \\ []) do
    case normalize_name(name) do
      {:ok, _valid_name} ->
        :ok

      {:error, %{message: message}} when is_binary(message) ->
        {:error, message}
    end
  end

  defp normalize_name(name) when is_binary(name) do
    if Regex.match?(@topology_name_regex, name) do
      {:ok, name}
    else
      {:error,
       Jido.Error.validation_error(
         "The name must start with a letter and contain only letters, numbers, and underscores.",
         field: :name
       )}
    end
  end

  defp normalize_name(other) do
    {:error,
     Jido.Error.validation_error("Topology name must be a string.", details: %{name: other})}
  end

  defp normalize_nodes(nodes) when is_map(nodes) do
    Enum.reduce_while(nodes, {:ok, %{}}, fn {name, attrs}, {:ok, acc} ->
      if is_atom(name) do
        case Node.new(name, attrs) do
          {:ok, node} -> {:cont, {:ok, Map.put(acc, name, node)}}
          {:error, _reason} = error -> {:halt, error}
        end
      else
        {:halt,
         {:error,
          Jido.Error.validation_error(
            "Topology node names must be atoms.",
            details: %{name: name}
          )}}
      end
    end)
  end

  defp normalize_nodes(other) do
    {:error,
     Jido.Error.validation_error("Topology nodes must be a map.", details: %{nodes: other})}
  end

  defp normalize_defaults(defaults) when is_map(defaults), do: {:ok, defaults}

  defp normalize_defaults(other) do
    {:error,
     Jido.Error.validation_error("Topology defaults must be a map.", details: %{defaults: other})}
  end

  defp normalize_links(links) when is_list(links), do: {:ok, links}

  defp normalize_links(other) do
    {:error,
     Jido.Error.validation_error("Topology links must be a list.", details: %{links: other})}
  end
end

defmodule Jido.Pod.Topology do
  @moduledoc """
  Canonical pod topology data structure.

  Topologies are pure data. They define the named durable nodes that a pod
  manages and can be validated, stored, and mutated independently of runtime
  process state.
  """

  alias Jido.Pod.Topology.{Link, Node}

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
                Zoi.list(Link.schema(), description: "Optional topology links.")
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
         {:ok, links} <- normalize_links(Map.get(attrs, :links, []), nodes) do
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
    %{
      topology
      | nodes: Map.delete(topology.nodes, name),
        links: Enum.reject(topology.links, &(&1.from == name or &1.to == name))
    }
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
  @spec put_link(t(), Link.t() | tuple() | keyword() | map()) :: {:ok, t()} | {:error, term()}
  def put_link(%__MODULE__{} = topology, link) do
    with {:ok, normalized_link} <- Link.new(link),
         :ok <- validate_link_endpoints(normalized_link, topology.nodes) do
      if normalized_link in topology.links do
        {:ok, topology}
      else
        {:ok, %{topology | links: topology.links ++ [normalized_link]}}
      end
    end
  end

  @doc """
  Removes a link from the topology.
  """
  @spec delete_link(t(), Link.t() | tuple() | keyword() | map()) :: t()
  def delete_link(%__MODULE__{} = topology, link) do
    normalized_link =
      case Link.new(link) do
        {:ok, parsed_link} -> parsed_link
        {:error, _reason} -> link
      end

    %{topology | links: Enum.reject(topology.links, &(&1 == normalized_link))}
  end

  @doc """
  Orders the given node names according to `:depends_on` links.

  Only dependencies between the provided node names participate in ordering.
  Other links are ignored.
  """
  @spec dependency_order(t(), [atom()]) :: {:ok, [atom()]} | {:error, term()}
  def dependency_order(%__MODULE__{} = topology, node_names) when is_list(node_names) do
    ordered_names = Enum.uniq(node_names)

    with :ok <- validate_dependency_targets(ordered_names, topology.nodes) do
      dependency_links =
        Enum.filter(topology.links, fn %Link{type: type, from: from, to: to} ->
          type == :depends_on and from in ordered_names and to in ordered_names
        end)

      adjacency =
        Enum.reduce(dependency_links, %{}, fn %Link{from: from, to: to}, acc ->
          Map.update(acc, to, [from], &[from | &1])
        end)

      indegree =
        Enum.reduce(ordered_names, %{}, fn name, acc -> Map.put(acc, name, 0) end)
        |> then(fn base ->
          Enum.reduce(dependency_links, base, fn %Link{from: from}, acc ->
            Map.update!(acc, from, &(&1 + 1))
          end)
        end)

      case topological_order(ordered_names, adjacency, indegree, []) do
        {:ok, ordered} ->
          {:ok, ordered}

        {:error, _reason} ->
          {:error,
           Jido.Error.validation_error(
             "Topology contains cyclic :depends_on links.",
             details: %{nodes: ordered_names, links: dependency_links}
           )}
      end
    end
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

  defp normalize_links(links, nodes) when is_list(links) and is_map(nodes) do
    Enum.reduce_while(links, {:ok, []}, fn link, {:ok, acc} ->
      with {:ok, parsed_link} <- Link.new(link),
           :ok <- validate_link_endpoints(parsed_link, nodes) do
        links =
          if parsed_link in acc do
            acc
          else
            acc ++ [parsed_link]
          end

        {:cont, {:ok, links}}
      else
        {:error, _reason} = error ->
          {:halt, error}
      end
    end)
  end

  defp normalize_links(other, _nodes) do
    {:error,
     Jido.Error.validation_error("Topology links must be a list.", details: %{links: other})}
  end

  defp validate_link_endpoints(%Link{from: from, to: to}, nodes) when is_map(nodes) do
    cond do
      not Map.has_key?(nodes, from) ->
        {:error,
         Jido.Error.validation_error(
           "Topology link source node does not exist.",
           details: %{from: from}
         )}

      not Map.has_key?(nodes, to) ->
        {:error,
         Jido.Error.validation_error(
           "Topology link target node does not exist.",
           details: %{to: to}
         )}

      true ->
        :ok
    end
  end

  defp validate_dependency_targets(node_names, nodes)
       when is_list(node_names) and is_map(nodes) do
    Enum.reduce_while(node_names, :ok, fn name, :ok ->
      if Map.has_key?(nodes, name) do
        {:cont, :ok}
      else
        {:halt,
         {:error,
          Jido.Error.validation_error(
            "Topology dependency ordering referenced an unknown node.",
            details: %{name: name}
          )}}
      end
    end)
  end

  defp topological_order([], _adjacency, _indegree, acc), do: {:ok, Enum.reverse(acc)}

  defp topological_order(remaining, adjacency, indegree, acc) do
    case Enum.find(remaining, &(Map.get(indegree, &1, 0) == 0)) do
      nil ->
        {:error, :cyclic_dependencies}

      next ->
        next_indegree =
          Enum.reduce(Map.get(adjacency, next, []), indegree, fn dependent, acc_indegree ->
            Map.update!(acc_indegree, dependent, &(&1 - 1))
          end)

        topological_order(List.delete(remaining, next), adjacency, next_indegree, [next | acc])
    end
  end
end

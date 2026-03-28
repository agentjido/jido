defmodule Jido.Pod.Mutation do
  @moduledoc """
  Public mutation types for live pod topology changes.
  """

  alias Jido.Pod.Topology
  alias Jido.Pod.Topology.Node

  defguardp is_node_name(name) when is_atom(name) or is_binary(name)

  @type node_name :: Topology.node_name()

  defmodule AddNode do
    @moduledoc """
    Add a new node to a running pod topology.
    """

    @node_name_schema Zoi.union([
                        Zoi.atom(description: "Logical node name."),
                        Zoi.string(description: "Logical node name.")
                      ])

    @schema Zoi.struct(
              __MODULE__,
              %{
                name: @node_name_schema,
                node: Zoi.any(description: "Topology node struct or attrs."),
                owner: @node_name_schema |> Zoi.optional(),
                depends_on:
                  Zoi.list(@node_name_schema, description: "Dependency node names.")
                  |> Zoi.default([])
              },
              coerce: true
            )

    @type t :: unquote(Zoi.type_spec(@schema))
    @enforce_keys Zoi.Struct.enforce_keys(@schema)
    defstruct Zoi.Struct.struct_fields(@schema)

    @spec schema() :: Zoi.schema()
    def schema, do: @schema
  end

  defmodule RemoveNode do
    @moduledoc """
    Remove a node and its owned subtree from a running pod topology.
    """

    @schema Zoi.struct(
              __MODULE__,
              %{
                name:
                  Zoi.union([
                    Zoi.atom(description: "Logical node name."),
                    Zoi.string(description: "Logical node name.")
                  ])
              },
              coerce: true
            )

    @type t :: unquote(Zoi.type_spec(@schema))
    @enforce_keys Zoi.Struct.enforce_keys(@schema)
    defstruct Zoi.Struct.struct_fields(@schema)

    @spec schema() :: Zoi.schema()
    def schema, do: @schema
  end

  defmodule Report do
    @moduledoc """
    Report returned from live pod mutation calls.
    """

    @node_name_schema Zoi.union([
                        Zoi.atom(description: "Logical node name."),
                        Zoi.string(description: "Logical node name.")
                      ])

    @schema Zoi.struct(
              __MODULE__,
              %{
                mutation_id: Zoi.string(description: "Mutation identifier."),
                status: Zoi.atom(description: "Mutation status."),
                topology_version: Zoi.integer(description: "Resulting topology version."),
                requested_ops:
                  Zoi.list(Zoi.any(), description: "Requested mutation operations.")
                  |> Zoi.default([]),
                added:
                  Zoi.list(@node_name_schema, description: "Nodes added by the mutation.")
                  |> Zoi.default([]),
                removed:
                  Zoi.list(@node_name_schema, description: "Nodes removed by the mutation.")
                  |> Zoi.default([]),
                started:
                  Zoi.list(@node_name_schema, description: "Nodes started by the mutation.")
                  |> Zoi.default([]),
                stopped:
                  Zoi.list(@node_name_schema, description: "Nodes stopped by the mutation.")
                  |> Zoi.default([]),
                failures: Zoi.map(description: "Node failures keyed by name.") |> Zoi.default(%{})
              },
              coerce: true
            )

    @type t :: unquote(Zoi.type_spec(@schema))
    @enforce_keys Zoi.Struct.enforce_keys(@schema)
    defstruct Zoi.Struct.struct_fields(@schema)

    @spec schema() :: Zoi.schema()
    def schema, do: @schema
  end

  defmodule Plan do
    @moduledoc false

    @enforce_keys [
      :mutation_id,
      :requested_ops,
      :current_topology,
      :final_topology,
      :added,
      :removed,
      :start_requested,
      :start_waves,
      :stop_waves,
      :removed_nodes,
      :report
    ]
    defstruct [
      :mutation_id,
      :requested_ops,
      :current_topology,
      :final_topology,
      :added,
      :removed,
      :start_requested,
      :start_waves,
      :stop_waves,
      :removed_nodes,
      :report
    ]

    @type t :: %__MODULE__{
            mutation_id: String.t(),
            requested_ops: [AddNode.t() | RemoveNode.t()],
            current_topology: Topology.t(),
            final_topology: Topology.t(),
            added: [Jido.Pod.Mutation.node_name()],
            removed: [Jido.Pod.Mutation.node_name()],
            start_requested: [Jido.Pod.Mutation.node_name()],
            start_waves: [[Jido.Pod.Mutation.node_name()]],
            stop_waves: [[Jido.Pod.Mutation.node_name()]],
            removed_nodes: %{Jido.Pod.Mutation.node_name() => Node.t()},
            report: Report.t()
          }
  end

  @type t :: AddNode.t() | RemoveNode.t()

  @spec add_node(node_name(), Node.t() | keyword() | map(), keyword()) :: AddNode.t()
  def add_node(name, node, opts \\ []) when is_node_name(name) and is_list(opts) do
    %AddNode{
      name: name,
      node: node,
      owner: Keyword.get(opts, :owner),
      depends_on: Keyword.get(opts, :depends_on, [])
    }
  end

  @spec remove_node(node_name()) :: RemoveNode.t()
  def remove_node(name) when is_node_name(name), do: %RemoveNode{name: name}

  @spec normalize_ops([term()]) :: {:ok, [t()]} | {:error, term()}
  def normalize_ops(ops) when is_list(ops) do
    Enum.reduce_while(ops, {:ok, []}, fn op, {:ok, acc} ->
      case normalize_op(op) do
        {:ok, normalized} -> {:cont, {:ok, [normalized | acc]}}
        {:error, _reason} = error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, normalized_ops} -> {:ok, Enum.reverse(normalized_ops)}
      {:error, _reason} = error -> error
    end
  end

  def normalize_ops(other) do
    {:error,
     Jido.Error.validation_error(
       "Pod mutation ops must be a list.",
       details: %{ops: other}
     )}
  end

  @spec normalize_op(term()) :: {:ok, t()} | {:error, term()}
  def normalize_op(%AddNode{} = op), do: {:ok, op}
  def normalize_op(%RemoveNode{} = op), do: {:ok, op}

  def normalize_op(attrs) when is_list(attrs) do
    normalize_op(Map.new(attrs))
  end

  def normalize_op(attrs) when is_map(attrs) do
    attrs = Map.new(attrs)

    cond do
      Map.has_key?(attrs, :node) or Map.has_key?(attrs, "node") ->
        Zoi.parse(AddNode.schema(), normalize_map_keys(attrs))

      mutation_kind(attrs) in [:remove, :remove_node] ->
        Zoi.parse(RemoveNode.schema(), normalize_map_keys(attrs))

      true ->
        {:error,
         Jido.Error.validation_error(
           "Could not infer pod mutation op type.",
           details: %{op: attrs}
         )}
    end
  end

  def normalize_op(other) do
    {:error,
     Jido.Error.validation_error(
       "Unsupported pod mutation op.",
       details: %{op: other}
     )}
  end

  defp mutation_kind(attrs) do
    attrs
    |> Enum.find_value(fn
      {:type, value} -> value
      {"type", value} -> value
      {:op, value} -> value
      {"op", value} -> value
      {:action, value} -> value
      {"action", value} -> value
      _other -> nil
    end)
    |> normalize_kind()
  end

  defp normalize_kind(kind) when kind in [:remove, :remove_node], do: kind
  defp normalize_kind("remove"), do: :remove
  defp normalize_kind("remove_node"), do: :remove_node
  defp normalize_kind(_other), do: nil

  defp normalize_map_keys(attrs) do
    Map.new(attrs, fn
      {key, value} when is_binary(key) ->
        atom_key =
          try do
            String.to_existing_atom(key)
          rescue
            ArgumentError -> key
          end

        {atom_key, value}

      pair ->
        pair
    end)
  end
end

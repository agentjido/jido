defmodule Jido.Pod.Topology.Node do
  @moduledoc """
  Canonical node definition for a pod topology.

  V1 nodes are durable named collaborators managed through
  `Jido.Agent.InstanceManager`. The shape is intentionally small but future
  compatible with richer topology kinds.
  """

  @valid_activations [:eager, :lazy]
  @valid_kinds [:agent, :pod]

  @schema Zoi.struct(
            __MODULE__,
            %{
              name: Zoi.atom(description: "The logical node name."),
              kind:
                Zoi.atom(description: "The node kind.")
                |> Zoi.default(:agent)
                |> Zoi.refine({__MODULE__, :validate_kind, []}),
              module: Zoi.atom(description: "The agent or pod module for this node."),
              manager:
                Zoi.atom(description: "The Jido.Agent.InstanceManager responsible for this node."),
              activation:
                Zoi.atom(description: "When the node should be activated.")
                |> Zoi.default(:lazy)
                |> Zoi.refine({__MODULE__, :validate_activation, []}),
              meta:
                Zoi.map(description: "Metadata applied when the node is adopted.")
                |> Zoi.default(%{}),
              initial_state:
                Zoi.map(description: "Initial state used when a node starts fresh.")
                |> Zoi.default(%{})
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
  Builds a validated topology node.
  """
  @spec new(atom(), keyword() | map()) :: {:ok, t()} | {:error, term()}
  def new(name, attrs) when is_atom(name) and is_list(attrs) do
    new(name, Map.new(attrs))
  end

  def new(name, attrs) when is_atom(name) and is_map(attrs) do
    attrs =
      attrs
      |> Map.new()
      |> normalize_module_alias()
      |> Map.put(:name, name)
      |> Map.put_new(:kind, :agent)
      |> Map.put_new(:activation, :lazy)
      |> Map.put_new(:meta, %{})
      |> Map.put_new(:initial_state, %{})

    Zoi.parse(@schema, attrs)
  end

  def new(name, _attrs) do
    {:error,
     Jido.Error.validation_error(
       "Invalid topology node for #{inspect(name)}; expected a map or keyword list."
     )}
  end

  @doc """
  Builds a validated topology node, raising on error.
  """
  @spec new!(atom(), keyword() | map()) :: t()
  def new!(name, attrs) do
    case new(name, attrs) do
      {:ok, node} ->
        node

      {:error, reason} ->
        raise Jido.Error.validation_error("Invalid topology node", details: reason)
    end
  end

  @doc false
  @spec validate_activation(atom(), keyword()) :: :ok | {:error, String.t()}
  def validate_activation(value, _opts \\ [])
  def validate_activation(value, _opts) when value in @valid_activations, do: :ok

  def validate_activation(value, _opts) do
    {:error,
     "expected activation to be one of #{inspect(@valid_activations)}, got: #{inspect(value)}"}
  end

  @doc false
  @spec validate_kind(atom(), keyword()) :: :ok | {:error, String.t()}
  def validate_kind(value, _opts \\ [])
  def validate_kind(value, _opts) when value in @valid_kinds, do: :ok

  def validate_kind(value, _opts) do
    {:error, "expected kind to be one of #{inspect(@valid_kinds)}, got: #{inspect(value)}"}
  end

  defp normalize_module_alias(%{module: _module} = attrs), do: attrs

  defp normalize_module_alias(%{agent: module} = attrs) do
    attrs
    |> Map.put(:module, module)
    |> Map.delete(:agent)
  end

  defp normalize_module_alias(attrs), do: attrs
end

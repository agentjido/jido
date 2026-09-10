defmodule Jido.Agent.Codec.Registry do
  @moduledoc """
  A trusted map of stable authoring identifiers to Agent modules, executables,
  Plugins, schemas, route matches, data atoms, and static struct values.

  Stored documents cannot create atoms or derive module names. An `:alias`
  entry points directly to a canonical identifier and is used only for reads.

      Jido.Agent.Codec.Registry.new!(%{
        "agents/counter" => {:agent, MyApp.Counter},
        "actions/add" => {:action, MyApp.Add},
        "schemas/count" => {:schema, MyApp.Counter.schema()},
        "atoms/amount" => {:atom, :amount}
      })
  """
  alias Jido.Agent.Authoring

  @kinds [:agent, :action, :flow, :plugin, :schema, :route_match, :atom, :value]
  @schema Zoi.struct(__MODULE__, %{entries: Zoi.map()})
  @type kind :: :agent | :action | :flow | :plugin | :schema | :route_match | :atom | :value
  @type t :: unquote(Zoi.type_spec(@schema))
  @enforce_keys Zoi.Struct.enforce_keys(@schema)
  defstruct Zoi.Struct.struct_fields(@schema)

  @doc "Returns the Registry schema."
  @spec schema() :: Zoi.schema()
  def schema, do: @schema

  @doc "Validates a trusted identifier map."
  @spec new(map() | t()) :: {:ok, t()} | {:error, Exception.t()}
  def new(%__MODULE__{entries: entries}), do: new(entries)

  def new(entries)
      when is_map(entries) and not is_struct(entries) and map_size(entries) <= 10_000 do
    with {:ok, _} <- Authoring.traverse(Enum.to_list(entries), &validate_entry/1),
         :ok <- unique_values(entries),
         :ok <- aliases(entries) do
      {:ok, %__MODULE__{entries: entries}}
    end
  end

  def new(_entries), do: Authoring.error("Registry must contain at most 10000 entries")

  @doc "Validates a Registry or raises its error."
  @spec new!(map() | t()) :: t() | no_return()
  def new!(entries) do
    case new(entries) do
      {:ok, registry} -> registry
      {:error, error} -> raise error
    end
  end

  @doc "Resolves a stored identifier of the required kind."
  @spec resolve(t(), String.t(), kind()) :: {:ok, term()} | {:error, term()}
  def resolve(%__MODULE__{entries: entries}, id, kind) do
    entry =
      case Map.get(entries, id) do
        {:alias, canonical} -> Map.get(entries, canonical)
        value -> value
      end

    case entry do
      {^kind, value} -> {:ok, value}
      _ -> Authoring.error("Unknown or mismatched Registry identifier", %{id: id, kind: kind})
    end
  end

  @doc "Finds the canonical identifier for a trusted value."
  @spec identifier(t(), kind(), term()) :: {:ok, String.t()} | {:error, term()}
  def identifier(%__MODULE__{entries: entries}, kind, value) do
    case Enum.find(entries, fn {_id, entry} -> entry === {kind, value} end) do
      {id, _} -> {:ok, id}
      nil -> Authoring.error("Registry has no identifier for value", %{kind: kind})
    end
  end

  defp validate_entry({id, {kind, value}}) when kind in @kinds do
    with :ok <- identifier_valid(id), :ok <- value_valid(kind, value), do: {:ok, id}
  end

  defp validate_entry({id, {:alias, value}}) do
    with :ok <- identifier_valid(id), :ok <- identifier_valid(value), do: {:ok, id}
  end

  defp validate_entry(_entry), do: Authoring.error("Invalid Registry entry")

  defp identifier_valid(id) when is_binary(id) and byte_size(id) in 1..255 do
    if String.valid?(id), do: :ok, else: Authoring.error("Invalid Registry identifier")
  end

  defp identifier_valid(_id), do: Authoring.error("Invalid Registry identifier")

  defp value_valid(:atom, value) when is_atom(value), do: :ok
  defp value_valid(:schema, value), do: Jido.Agent.State.validate_schema(value)

  defp value_valid(:value, value) when is_struct(value) do
    case Jido.Action.validate_static_data(value) do
      :ok -> :ok
      _ -> Authoring.error("Registry value must contain static data")
    end
  end

  defp value_valid(:route_match, value) when is_function(value, 1) do
    if Function.info(value, :type) == {:type, :external},
      do: :ok,
      else: Authoring.error("Route matches must be external unary captures")
  end

  defp value_valid(:agent, value) when is_atom(value) do
    if agent_module?(value),
      do: :ok,
      else: Authoring.error("Invalid Registry module", %{kind: :agent})
  end

  defp value_valid(:plugin, value) when is_atom(value) do
    if Code.ensure_loaded?(value) and function_exported?(value, :__jido_plugin__, 0),
      do: :ok,
      else: Authoring.error("Invalid Registry module", %{kind: :plugin})
  end

  defp value_valid(kind, value) when kind in [:action, :flow] do
    with {:ok, %{kind: ^kind}} <- Jido.Executable.resolve(value),
         :ok <- Jido.Executable.validate(value) do
      :ok
    else
      _ -> Authoring.error("Invalid Registry executable", %{kind: kind})
    end
  end

  defp value_valid(kind, _value), do: Authoring.error("Invalid Registry value", %{kind: kind})

  defp agent_module?(Jido.Agent), do: true

  defp agent_module?(module) do
    Code.ensure_loaded?(module) and
      (function_exported?(module, :handle_signal, 2) or
         module.module_info(:attributes)
         |> Keyword.get_values(:behaviour)
         |> List.flatten()
         |> Enum.member?(Jido.Agent))
  end

  defp unique_values(entries) do
    values = entries |> Map.values() |> Enum.reject(&match?({:alias, _}, &1))

    if length(values) == length(Enum.uniq(values)),
      do: :ok,
      else: Authoring.error("Registry values must have one canonical identifier")
  end

  defp aliases(entries) do
    if Enum.all?(entries, fn
         {_id, {:alias, target}} ->
           match?({kind, _} when kind in @kinds, Map.get(entries, target))

         _ ->
           true
       end),
       do: :ok,
       else: Authoring.error("Registry aliases must refer directly to a canonical entry")
  end
end

defmodule Jido.Catalog.Entry do
  @moduledoc """
  One stable definition in a Jido Catalog.

  An Entry identifies a trusted target by stable ID, version, and kind. The
  provider and OTP application make package contributions inspectable.
  """

  @identifier_pattern ~r/\A[A-Za-z0-9][A-Za-z0-9._\/:@-]{0,254}\z/
  @fields [:id, :vsn, :kind, :target, :provider, :application, :name, :description]
  @required_fields [:id, :vsn, :kind, :target, :provider, :application]

  alias Jido.Joi
  alias Jido.Joi.Static

  @enforce_keys @required_fields
  defstruct @required_fields ++ [name: nil, description: nil]

  @type stable_id :: String.t()
  @type version :: pos_integer()
  @type kind :: atom()
  @type ref :: {stable_id(), version()}

  @type t :: %__MODULE__{
          id: stable_id(),
          vsn: version(),
          kind: kind(),
          target: term(),
          provider: module(),
          application: atom(),
          name: String.t() | nil,
          description: String.t() | nil
        }

  @doc "Builds one validated Catalog Entry."
  @spec new(map() | t()) :: {:ok, t()} | {:error, term()}
  def new(%__MODULE__{} = entry), do: validate(entry)

  def new(%{} = attrs) when not is_struct(attrs) do
    unknown = Map.keys(attrs) -- @fields
    missing = @required_fields -- Map.keys(attrs)

    cond do
      unknown != [] ->
        {:error, {:invalid_catalog_entry, :unknown_fields, Enum.sort(unknown)}}

      missing != [] ->
        {:error, {:invalid_catalog_entry, :missing_fields, missing}}

      true ->
        attrs
        |> then(&struct(__MODULE__, &1))
        |> validate()
    end
  end

  def new(_attrs), do: {:error, {:invalid_catalog_entry, :entry, :map}}

  @doc "Builds one validated Catalog Entry or raises `ArgumentError`."
  @spec new!(map() | t()) :: t()
  def new!(attrs) do
    case new(attrs) do
      {:ok, entry} -> entry
      {:error, reason} -> raise ArgumentError, "invalid Catalog Entry: #{inspect(reason)}"
    end
  end

  @doc "Returns the stable ID and version reference."
  @spec reference(t()) :: ref()
  def reference(%__MODULE__{id: id, vsn: vsn}), do: {id, vsn}

  @doc false
  @spec sort_key(t()) :: tuple()
  def sort_key(%__MODULE__{} = entry) do
    {
      entry.id,
      entry.vsn,
      Atom.to_string(entry.kind),
      Atom.to_string(entry.application),
      Atom.to_string(entry.provider)
    }
  end

  @doc false
  @spec valid_identifier?(term()) :: boolean()
  def valid_identifier?(id),
    do: is_binary(id) and byte_size(id) in 1..255 and Regex.match?(@identifier_pattern, id)

  defp validate(%__MODULE__{} = entry) do
    cond do
      not valid_identifier?(entry.id) ->
        {:error, {:invalid_catalog_entry, :id, entry.id}}

      not (is_integer(entry.vsn) and entry.vsn > 0) ->
        {:error, {:invalid_catalog_entry, :vsn, entry.vsn}}

      not valid_kind?(entry.kind) ->
        {:error, {:invalid_catalog_entry, :kind, entry.kind}}

      is_nil(entry.target) ->
        {:error, {:invalid_catalog_entry, :target, nil}}

      not valid_atom?(entry.provider) ->
        {:error, {:invalid_catalog_entry, :provider, entry.provider}}

      not valid_atom?(entry.application) ->
        {:error, {:invalid_catalog_entry, :application, entry.application}}

      not valid_text?(entry.name) ->
        {:error, {:invalid_catalog_entry, :name, :utf8_string}}

      not valid_text?(entry.description) ->
        {:error, {:invalid_catalog_entry, :description, :utf8_string}}

      true ->
        validate_target(entry)
    end
  end

  defp validate_target(%__MODULE__{kind: kind, target: target} = entry)
       when kind in [:action, :flow] do
    if valid_atom?(target),
      do: {:ok, entry},
      else: {:error, {:invalid_catalog_entry, :target, "Action and Flow targets must be modules"}}
  end

  defp validate_target(%__MODULE__{kind: :atom, target: target} = entry) do
    if valid_atom?(target),
      do: {:ok, entry},
      else: {:error, {:invalid_catalog_entry, :target, "atom targets must be non-Boolean atoms"}}
  end

  defp validate_target(%__MODULE__{kind: :schema, target: target} = entry) do
    with :ok <- Static.validate(target),
         true <- Joi.Schema.schema?(target),
         true <- Joi.Schema.map_shaped?(target) do
      {:ok, entry}
    else
      {:error, reason} -> {:error, {:invalid_catalog_entry, :target, reason}}
      false -> {:error, {:invalid_catalog_entry, :target, "schema targets must accept map-shaped data"}}
    end
  end

  defp validate_target(%__MODULE__{target: target} = entry) do
    case Static.validate(target) do
      :ok -> {:ok, entry}
      {:error, reason} -> {:error, {:invalid_catalog_entry, :target, reason}}
    end
  end

  defp valid_atom?(value), do: is_atom(value) and value not in [nil, true, false]
  defp valid_kind?(value), do: valid_atom?(value) and value != :alias
  defp valid_text?(nil), do: true
  defp valid_text?(value), do: is_binary(value) and String.valid?(value)
end

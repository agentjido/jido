defmodule Jido.Catalog.Entry do
  @moduledoc "One explicitly registered value and its source."
  @identifier_pattern ~r/\A[A-Za-z0-9][A-Za-z0-9._\/:@-]{0,254}\z/
  @fields [:id, :vsn, :target, :provider, :application]
  @enforce_keys @fields
  defstruct @fields
  @type ref :: {String.t(), pos_integer()}
  @type t :: %__MODULE__{id: String.t(), vsn: pos_integer(), target: term(), provider: module(), application: atom()}

  @doc "Builds a registration. Named values default to Provider/name; modules use their full name."
  def new(%__MODULE__{} = entry), do: validate(entry)

  def new(attrs) when is_map(attrs) and not is_struct(attrs) do
    attrs = attrs |> Map.put_new(:vsn, 1) |> default_id()
    unknown = Map.keys(attrs) -- @fields
    missing = @fields -- Map.keys(attrs)

    cond do
      unknown != [] -> {:error, {:invalid_catalog_entry, :unknown_fields, Enum.sort(unknown)}}
      missing != [] -> {:error, {:invalid_catalog_entry, :missing_fields, missing}}
      true -> validate(struct!(__MODULE__, attrs))
    end
  end

  def new(_), do: {:error, {:invalid_catalog_entry, :entry, :map}}

  @doc "Builds a registration or raises."
  def new!(attrs) do
    case new(attrs) do
      {:ok, entry} -> entry
      {:error, reason} -> raise ArgumentError, "invalid Catalog Entry: #{inspect(reason)}"
    end
  end

  def reference(%__MODULE__{id: id, vsn: vsn}), do: {id, vsn}
  @doc false
  def sort_key(entry), do: {entry.id, entry.vsn, entry.application, entry.provider}
  @doc false
  def valid_identifier?(id), do: is_binary(id) and byte_size(id) in 1..255 and Regex.match?(@identifier_pattern, id)

  defp default_id(attrs) do
    {name, attrs} = Map.pop(attrs, :name)

    Map.put_new_lazy(attrs, :id, fn ->
      target = Map.get(attrs, :target)
      provider = Map.get(attrs, :provider)

      cond do
        not valid_atom?(provider) ->
          nil

        is_binary(name) or (is_atom(name) and not is_nil(name)) ->
          "#{provider}/#{name}"

        is_atom(target) and not is_nil(target) ->
          value = Atom.to_string(target)
          if String.starts_with?(value, "Elixir."), do: value, else: "#{provider}/#{value}"

        true ->
          nil
      end
    end)
  end

  defp validate(entry) do
    cond do
      not valid_atom?(entry.provider) -> {:error, {:invalid_catalog_entry, :provider, entry.provider}}
      not valid_identifier?(entry.id) -> {:error, {:invalid_catalog_entry, :id, entry.id}}
      not (is_integer(entry.vsn) and entry.vsn > 0) -> {:error, {:invalid_catalog_entry, :vsn, entry.vsn}}
      not valid_atom?(entry.application) -> {:error, {:invalid_catalog_entry, :application, entry.application}}
      true -> {:ok, entry}
    end
  end

  defp valid_atom?(value), do: is_atom(value) and value not in [nil, true, false]
end

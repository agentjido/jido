defmodule Jido.Catalog do
  @moduledoc """
  A passive registry of explicitly registered values, identified by ID and version.

  Catalog does not discover, load, authorize, or validate the domain role of a
  target. The consumer validates the value after resolution. Discovery builds
  and publishes the application Catalog; callers can supply a Catalog explicitly.
  """
  alias Jido.Catalog.{Entry, Error, Manifest}
  @maximum_entries 10_000
  @enforce_keys [:entries, :targets]
  defstruct @enforce_keys
  @type key :: Entry.ref()
  @type t :: %__MODULE__{entries: %{key() => Entry.t()}, targets: %{term() => Entry.t()}}
  @type source :: t() | :current

  @doc "Builds a Catalog from registered Entries or package Manifests."
  def new(values) when is_list(values) do
    if List.improper?(values) do
      {:error, {:invalid_catalog, :improper_list}}
    else
      with {:ok, entries} <- flatten(values), do: build(entries)
    end
  end

  def new(_), do: {:error, {:invalid_catalog, :list}}

  @doc "Builds a Catalog or raises."
  def new!(values) do
    case new(values) do
      {:ok, catalog} -> catalog
      {:error, reason} -> raise ArgumentError, "invalid Catalog: #{inspect(reason)}"
    end
  end

  @doc "Builds an explicit Catalog from a map of {ID, version} to value."
  def from_targets(provider, application, targets) when is_map(targets) and not is_struct(targets) do
    entries =
      Enum.map(targets, fn
        {{id, vsn}, target} -> %{id: id, vsn: vsn, target: target}
        {reference, _} -> %{invalid_reference: reference}
      end)

    with {:ok, manifest} <- Manifest.new(provider, application, entries), do: new([manifest])
  end

  def from_targets(_, _, _), do: error("Catalog targets must be a map")

  @doc "Builds an explicit Catalog from targets or raises."
  def from_targets!(provider, application, targets) do
    case from_targets(provider, application, targets) do
      {:ok, catalog} -> catalog
      {:error, reason} -> raise ArgumentError, "invalid Catalog targets: #{inspect(reason)}"
    end
  end

  @doc "Returns the Entry for an exact ID and version."
  def get(%__MODULE__{entries: entries}, id, vsn), do: Map.get(entries, {id, vsn})

  @doc "Returns a registered Entry for a value. Aliases use the first sorted reference."
  def get_by_target(%__MODULE__{targets: targets}, target), do: Map.get(targets, target)

  @doc "Resolves an exact registered reference. The consumer validates its role."
  def resolve(%__MODULE__{entries: entries}, reference) do
    with {:ok, {id, vsn} = key} <- validate_reference(reference) do
      case Map.fetch(entries, key) do
        {:ok, entry} -> {:ok, entry.target}
        :error -> missing_reference(entries, id, vsn)
      end
    end
  end

  @doc "Returns a registered reference for a value."
  def reference(%__MODULE__{} = catalog, target) do
    case get_by_target(catalog, target) do
      nil -> error("Catalog has no reference for the required target")
      entry -> {:ok, Entry.reference(entry)}
    end
  end

  @doc "Lists registrations in ID and version order."
  def list(%__MODULE__{entries: entries}), do: entries |> Map.values() |> Enum.sort_by(&Entry.reference/1)

  @doc false
  @spec validate_reference(term()) :: {:ok, key()} | {:error, Error.t()}
  def validate_reference({id, vsn}) do
    with :ok <- validate_identifier(id),
         :ok <- validate_vsn(vsn),
         do: {:ok, {id, vsn}}
  end

  def validate_reference(reference),
    do: error("invalid Catalog reference", %{reference: value_type(reference)})

  @doc false
  @spec validate_identifier(term()) :: :ok | {:error, Error.t()}
  def validate_identifier(id) do
    if Entry.valid_identifier?(id),
      do: :ok,
      else: error("invalid Catalog identifier", %{identifier: value_type(id), field: "id"})
  end

  @doc false
  @spec validate_vsn(term()) :: :ok | {:error, Error.t()}
  def validate_vsn(vsn) when is_integer(vsn) and vsn > 0, do: :ok
  def validate_vsn(vsn), do: error("invalid Catalog vsn", %{vsn: vsn, field: "vsn"})

  defp missing_reference(entries, id, vsn) do
    supported = for {^id, version} <- Map.keys(entries), do: version

    if supported == [] do
      error("unknown Catalog reference", %{identifier: id, vsn: vsn, field: "id"})
    else
      error("Catalog reference has unsupported vsn", %{
        identifier: id,
        vsn: vsn,
        supported_vsns: Enum.sort(supported),
        field: "vsn"
      })
    end
  end

  defp value_type(value) when is_atom(value), do: :atom
  defp value_type(value) when is_binary(value), do: :binary
  defp value_type(value) when is_integer(value), do: :integer
  defp value_type(value) when is_list(value), do: :list
  defp value_type(value) when is_map(value), do: :map
  defp value_type(value) when is_tuple(value), do: :tuple
  defp value_type(_value), do: :other

  defp error(message, details \\ %{}),
    do: {:error, Error.exception(message: message, details: details)}

  defp flatten(values) do
    Enum.reduce_while(values, {:ok, []}, fn
      %Manifest{entries: entries}, {:ok, acc} -> {:cont, {:ok, entries ++ acc}}
      %Entry{} = entry, {:ok, acc} -> {:cont, {:ok, [entry | acc]}}
      value, _ -> {:halt, {:error, {:invalid_catalog_value, value}}}
    end)
  end

  defp build(entries) when length(entries) > @maximum_entries,
    do: {:error, {:catalog_limit, length(entries), @maximum_entries}}

  defp build(entries) do
    entries
    |> Enum.sort_by(&Entry.sort_key/1)
    |> Enum.reduce_while({:ok, %{}, %{}}, fn entry, {:ok, by_ref, by_target} ->
      with {:ok, entry} <- Entry.new(entry) do
        ref = Entry.reference(entry)

        case Map.fetch(by_ref, ref) do
          {:ok, previous} ->
            {:halt,
             {:error,
              {:catalog_conflict, ref, [{previous.provider, previous.application}, {entry.provider, entry.application}]}}}

          :error ->
            {:cont, {:ok, Map.put(by_ref, ref, entry), Map.put_new(by_target, entry.target, entry)}}
        end
      else
        {:error, _} = error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, entries, targets} -> {:ok, %__MODULE__{entries: entries, targets: targets}}
      error -> error
    end
  end
end

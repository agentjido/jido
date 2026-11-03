defmodule Jido.Catalog do
  @moduledoc """
  An immutable, revisioned inventory of trusted Jido definitions.

  A Catalog is inventory. Finding an Entry does not authorize its target.
  Callers must still apply application policy before execution.
  """

  alias Jido.Catalog.{Entry, Error, Manifest}

  @maximum_entries 10_000

  @enforce_keys [:entries, :references, :targets, :kinds, :revision]
  defstruct @enforce_keys

  @type key :: Entry.ref()
  @type t :: %__MODULE__{
          entries: %{key() => Entry.t()},
          references: %{{Entry.kind(), term()} => key()},
          targets: %{{Entry.kind(), term()} => Entry.t()},
          kinds: %{Entry.kind() => [key()]},
          revision: String.t()
        }

  @doc "Builds an immutable Catalog from Entries or Manifests."
  @spec new([Entry.t() | Manifest.t()]) :: {:ok, t()} | {:error, term()}
  def new(values) when is_list(values) do
    if List.improper?(values) do
      {:error, {:invalid_catalog, :improper_list}}
    else
      values
      |> flatten_values()
      |> build()
    end
  end

  def new(_values), do: {:error, {:invalid_catalog, :list}}

  @doc "Builds an immutable Catalog or raises `ArgumentError`."
  @spec new!([Entry.t() | Manifest.t()]) :: t()
  def new!(values) do
    case new(values) do
      {:ok, catalog} -> catalog
      {:error, reason} -> raise ArgumentError, "invalid Catalog: #{inspect(reason)}"
    end
  end

  @doc "Builds a Catalog from a compact map of owned typed targets."
  @spec from_targets(module(), atom(), %{optional(key()) => {Entry.kind(), term()}}) ::
          {:ok, t()} | {:error, term()}
  def from_targets(provider, application, targets)
      when is_map(targets) and not is_struct(targets) do
    entries =
      Enum.map(targets, fn
        {{id, vsn}, {kind, target}} ->
          %{id: id, vsn: vsn, kind: kind, target: target}

        {reference, value} ->
          %{invalid_reference: reference, invalid_value: value}
      end)

    with {:ok, manifest} <- Manifest.new(provider, application, entries),
         do: new([manifest])
  end

  def from_targets(_provider, _application, _targets),
    do: error("Catalog targets must be a map")

  @doc "Builds a Catalog from a compact target map or raises its error."
  @spec from_targets!(module(), atom(), %{optional(key()) => {Entry.kind(), term()}}) :: t()
  def from_targets!(provider, application, targets) do
    case from_targets(provider, application, targets) do
      {:ok, catalog} -> catalog
      {:error, %{__exception__: true} = exception} -> raise exception
      {:error, reason} -> raise ArgumentError, "invalid Catalog targets: #{inspect(reason)}"
    end
  end

  @doc "Returns the exact Entry for a stable ID and version."
  @spec get(t(), String.t(), pos_integer()) :: Entry.t() | nil
  def get(%__MODULE__{entries: entries}, id, vsn), do: Map.get(entries, {id, vsn})

  @doc "Returns the exact Entry when its kind also matches."
  @spec get(t(), Entry.kind(), String.t(), pos_integer()) :: Entry.t() | nil
  def get(%__MODULE__{} = catalog, kind, id, vsn) do
    case get(catalog, id, vsn) do
      %Entry{kind: ^kind} = entry -> entry
      _missing_or_wrong_kind -> nil
    end
  end

  @doc "Returns the Entry for one exact kind and target."
  @spec get_by_target(t(), Entry.kind(), term()) :: Entry.t() | nil
  def get_by_target(%__MODULE__{targets: targets}, kind, target),
    do: Map.get(targets, {kind, target})

  @doc "Resolves one exact reference of the required kind."
  @spec resolve(t(), key(), Entry.kind() | [Entry.kind()]) ::
          {:ok, term()} | {:error, Error.t()}
  def resolve(%__MODULE__{} = catalog, reference, kinds) when is_list(kinds) do
    with :ok <- validate_kinds(kinds),
         do: resolve_one(catalog, reference, kinds, kinds, List.last(kinds))
  end

  def resolve(%__MODULE__{} = catalog, reference, kind) do
    if valid_kind?(kind),
      do: resolve_one(catalog, reference, [kind], kind, kind),
      else: error("invalid Catalog reference", %{reference: value_type(reference), kind: kind})
  end

  @doc "Returns the stable reference for one target of an accepted kind."
  @spec reference(t(), Entry.kind() | [Entry.kind()], term()) ::
          {:ok, key()} | {:error, Error.t()}
  def reference(%__MODULE__{references: references}, kinds, target) when is_list(kinds) do
    with :ok <- validate_kinds(kinds),
         do: reference_one(references, kinds, target, %{kinds: kinds})
  end

  def reference(%__MODULE__{references: references}, kind, target) do
    if valid_kind?(kind),
      do: reference_one(references, [kind], target, %{kind: kind}),
      else: error("invalid Catalog kind", %{kind: kind})
  end

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

  defp resolve_one(%__MODULE__{entries: entries}, reference, kinds, expected, missing_kind) do
    with {:ok, {id, vsn} = key} <- validate_reference(reference) do
      case Map.fetch(entries, key) do
        {:ok, %Entry{kind: kind, target: target}} ->
          if kind in kinds do
            {:ok, target}
          else
            error("Catalog reference has the wrong entry kind", %{
              identifier: id,
              vsn: vsn,
              expected: expected,
              actual: kind,
              field: "id"
            })
          end

        :error ->
          missing_reference(entries, id, vsn, missing_kind)
      end
    end
  end

  defp reference_one(references, kinds, target, details) do
    case Enum.find_value(kinds, &Map.get(references, {&1, target})) do
      nil -> error("Catalog has no reference for the required target", details)
      reference -> {:ok, reference}
    end
  end

  defp missing_reference(entries, id, vsn, kind) do
    supported =
      entries
      |> Map.keys()
      |> Enum.flat_map(fn {entry_id, entry_vsn} ->
        if entry_id == id, do: [entry_vsn], else: []
      end)
      |> Enum.sort()

    if supported == [] do
      error("unknown Catalog reference", %{
        identifier: id,
        vsn: vsn,
        kind: kind,
        field: "id"
      })
    else
      error("Catalog reference has unsupported vsn", %{
        identifier: id,
        vsn: vsn,
        kind: kind,
        supported_vsns: supported,
        field: "vsn"
      })
    end
  end

  defp validate_kinds([]), do: error("invalid Catalog kinds", %{kinds: []})

  defp validate_kinds(kinds) do
    if Enum.all?(kinds, &valid_kind?/1),
      do: :ok,
      else: error("invalid Catalog kinds", %{kinds: kinds})
  end

  defp valid_kind?(kind),
    do: is_atom(kind) and kind not in [nil, true, false, :alias]

  defp value_type(value) when is_atom(value), do: :atom
  defp value_type(value) when is_binary(value), do: :binary
  defp value_type(value) when is_integer(value), do: :integer
  defp value_type(value) when is_list(value), do: :list
  defp value_type(value) when is_map(value), do: :map
  defp value_type(value) when is_tuple(value), do: :tuple
  defp value_type(_value), do: :other

  defp error(message, details \\ %{}),
    do: {:error, Error.exception(message: message, details: details)}

  @doc "Lists all Entries in deterministic order."
  @spec list(t()) :: [Entry.t()]
  def list(%__MODULE__{entries: entries}),
    do: entries |> Map.values() |> Enum.sort_by(&Entry.sort_key/1)

  @doc "Lists Entries of one kind in deterministic order."
  @spec list(t(), Entry.kind()) :: [Entry.t()]
  def list(%__MODULE__{} = catalog, kind), do: Enum.filter(list(catalog), &(&1.kind == kind))

  @doc "Returns the deterministic Catalog revision."
  @spec revision(t()) :: String.t()
  def revision(%__MODULE__{revision: revision}), do: revision

  defp flatten_values(values) do
    Enum.reduce_while(values, {:ok, []}, fn
      %Manifest{entries: entries}, {:ok, acc} -> {:cont, {:ok, entries ++ acc}}
      %Entry{} = entry, {:ok, acc} -> {:cont, {:ok, [entry | acc]}}
      value, _acc -> {:halt, {:error, {:invalid_catalog_value, value}}}
    end)
  end

  defp build({:error, _reason} = error), do: error

  defp build({:ok, entries}) when length(entries) > @maximum_entries,
    do: {:error, {:catalog_limit, length(entries), @maximum_entries}}

  defp build({:ok, entries}) do
    entries = Enum.sort_by(entries, &Entry.sort_key/1)

    with {:ok, entries_by_ref} <- index_references(entries),
         {:ok, references, targets} <- index_targets(entries) do
      kinds =
        entries
        |> Enum.group_by(& &1.kind, &Entry.reference/1)
        |> Map.new(fn {kind, references} -> {kind, Enum.sort(references)} end)

      {:ok,
       %__MODULE__{
         entries: entries_by_ref,
         references: references,
         targets: targets,
         kinds: kinds,
         revision: calculate_revision(entries)
       }}
    end
  end

  defp index_references(entries) do
    Enum.reduce_while(entries, {:ok, %{}}, fn entry, {:ok, indexed} ->
      reference = Entry.reference(entry)

      if Map.has_key?(indexed, reference),
        do: {:halt, {:error, {:catalog_conflict, :reference, reference}}},
        else: {:cont, {:ok, Map.put(indexed, reference, entry)}}
    end)
  end

  defp index_targets(entries) do
    Enum.reduce_while(entries, {:ok, %{}, %{}}, fn entry, {:ok, references, targets} ->
      key = {entry.kind, entry.target}

      case Map.fetch(references, key) do
        {:ok, existing} ->
          {:halt, {:error, {:catalog_conflict, :target, key, Enum.sort([existing, Entry.reference(entry)])}}}

        :error ->
          {:cont, {:ok, Map.put(references, key, Entry.reference(entry)), Map.put(targets, key, entry)}}
      end
    end)
  end

  defp calculate_revision(entries) do
    entries
    |> Enum.map(&Map.from_struct/1)
    |> :erlang.term_to_binary([:deterministic])
    |> then(&:crypto.hash(:sha256, &1))
    |> Base.url_encode64(padding: false)
  end
end

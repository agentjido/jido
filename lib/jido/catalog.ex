defmodule Jido.Catalog do
  @moduledoc """
  An immutable, revisioned inventory of trusted Jido definitions.

  A Catalog is inventory. Finding an Entry does not authorize its target.
  Callers must still apply application policy before execution.
  """

  alias Jido.Catalog.{Entry, Manifest}

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
          {:ok, term()} | {:error, :not_found | :wrong_kind}
  def resolve(%__MODULE__{} = catalog, {id, vsn}, kinds) do
    case get(catalog, id, vsn) do
      nil -> {:error, :not_found}
      %Entry{kind: kind, target: target} -> if kind in List.wrap(kinds), do: {:ok, target}, else: {:error, :wrong_kind}
    end
  end

  def resolve(%__MODULE__{}, _reference, _kinds), do: {:error, :not_found}

  @doc "Returns the stable reference for one exact kind and target."
  @spec reference(t(), Entry.kind(), term()) :: {:ok, key()} | {:error, :not_found}
  def reference(%__MODULE__{references: references}, kind, target) do
    case Map.fetch(references, {kind, target}) do
      {:ok, reference} -> {:ok, reference}
      :error -> {:error, :not_found}
    end
  end

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

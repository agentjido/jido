defmodule Jido.Catalog.View do
  @moduledoc """
  An immutable filtered view of a Jido Catalog.

  A View limits visible kinds and targets. It does not grant execution
  authority and must not replace application authorization.
  """

  alias Jido.Catalog
  alias Jido.Catalog.Entry

  @enforce_keys [:catalog, :kinds, :targets]
  defstruct @enforce_keys

  @type filter :: :all | MapSet.t(term())
  @type t :: %__MODULE__{catalog: Catalog.t(), kinds: filter(), targets: filter()}

  @doc "Builds a filtered View."
  @spec new(Catalog.t(), keyword()) :: {:ok, t()} | {:error, term()}
  def new(catalog, opts \\ [])

  def new(%Catalog{} = catalog, opts) do
    if Keyword.keyword?(opts) and Keyword.keys(opts) -- [:kinds, :targets] == [] do
      with {:ok, kinds} <- filter(Keyword.get(opts, :kinds, :all), :kinds),
           {:ok, targets} <- filter(Keyword.get(opts, :targets, :all), :targets) do
        {:ok, %__MODULE__{catalog: catalog, kinds: kinds, targets: targets}}
      end
    else
      {:error, {:invalid_catalog_view, :options}}
    end
  end

  def new(_catalog, _opts), do: {:error, {:invalid_catalog_view, :catalog}}

  @doc "Builds a View or raises `ArgumentError`."
  @spec new!(Catalog.t(), keyword()) :: t()
  def new!(catalog, opts \\ []) do
    case new(catalog, opts) do
      {:ok, view} -> view
      {:error, reason} -> raise ArgumentError, "invalid Catalog View: #{inspect(reason)}"
    end
  end

  @doc "Lists visible Entries in deterministic order."
  @spec list(t()) :: [Entry.t()]
  def list(%__MODULE__{catalog: catalog} = view), do: Enum.filter(Catalog.list(catalog), &allows?(view, &1))

  @doc "Lists visible Entries of one kind."
  @spec list(t(), Entry.kind()) :: [Entry.t()]
  def list(%__MODULE__{} = view, kind), do: Enum.filter(list(view), &(&1.kind == kind))

  @doc "Returns one visible Entry by reference."
  @spec get(t(), String.t(), pos_integer()) :: Entry.t() | nil
  def get(%__MODULE__{catalog: catalog} = view, id, vsn) do
    case Catalog.get(catalog, id, vsn) do
      %Entry{} = entry -> if allows?(view, entry), do: entry
      nil -> nil
    end
  end

  @doc "Returns one visible Entry by kind and target."
  @spec get_by_target(t(), Entry.kind(), term()) :: Entry.t() | nil
  def get_by_target(%__MODULE__{catalog: catalog} = view, kind, target) do
    case Catalog.get_by_target(catalog, kind, target) do
      %Entry{} = entry -> if allows?(view, entry), do: entry
      nil -> nil
    end
  end

  @doc "Returns true when an Entry is visible in the View."
  @spec allows?(t(), Entry.t()) :: boolean()
  def allows?(%__MODULE__{kinds: kinds, targets: targets}, %Entry{} = entry),
    do: member?(kinds, entry.kind) and member?(targets, entry.target)

  @doc "Returns the revision of the source Catalog."
  @spec revision(t()) :: String.t()
  def revision(%__MODULE__{catalog: catalog}), do: Catalog.revision(catalog)

  defp filter(:all, _name), do: {:ok, :all}

  defp filter(values, name) when is_list(values) do
    if List.improper?(values),
      do: {:error, {:invalid_catalog_view, name}},
      else: {:ok, MapSet.new(values)}
  end

  defp filter(_values, name), do: {:error, {:invalid_catalog_view, name}}

  defp member?(:all, _value), do: true
  defp member?(%MapSet{} = values, value), do: MapSet.member?(values, value)
end

defmodule Jido.Signal.Registry do
  @moduledoc """
  Registry for managing signal subscriptions.

  Provides functionality to register, unregister, and manage subscriptions
  to signal paths with associated dispatch configurations.
  """
  use TypedStruct
  use ExDbug, enabled: false

  typedstruct module: Subscription do
    @typedoc "A single subscription mapping a path to dispatch configuration"
    field(:id, String.t(), enforce: true)
    field(:path, String.t(), enforce: true)
    field(:dispatch, term(), enforce: true)
    field(:created_at, DateTime.t(), default: DateTime.utc_now())
  end

  typedstruct do
    @typedoc "Registry containing a unique mapping of subscription IDs to subscriptions"
    field(:subscriptions, %{String.t() => Subscription.t()}, default: %{})
  end

  @doc """
  Creates a new empty registry.

  ## Examples
      iex> registry = Jido.Signal.Registry.new()
  """
  def new do
    %__MODULE__{}
  end

  @doc """
  Registers a new subscription in the registry.

  ## Parameters
    * registry - The current registry
    * id - Unique identifier for the subscription
    * path - Signal path pattern to subscribe to
    * dispatch - Dispatch configuration for matched signals

  ## Returns
    * `{:ok, updated_registry}` - Subscription was added successfully
    * `{:error, :already_exists}` - A subscription with this ID already exists

  ## Examples
      iex> {:ok, registry} = Registry.register(registry, "sub1", "user.created", dispatch_config)
  """
  @spec register(t(), String.t(), String.t(), term()) :: {:ok, t()} | {:error, :already_exists}
  def register(%__MODULE__{} = registry, id, path, dispatch) do
    if Map.has_key?(registry.subscriptions, id) do
      {:error, :already_exists}
    else
      subscription = %Subscription{
        id: id,
        path: path,
        dispatch: dispatch
      }

      subscriptions = Map.put(registry.subscriptions, id, subscription)
      {:ok, %{registry | subscriptions: subscriptions}}
    end
  end

  @doc """
  Unregisters a subscription from the registry.

  ## Parameters
    * registry - The current registry
    * id - ID of the subscription to remove

  ## Returns
    * `{:ok, updated_registry}` - Subscription was removed successfully
    * `{:error, :not_found}` - No subscription with this ID exists

  ## Examples
      iex> {:ok, registry} = Registry.unregister(registry, "sub1")
  """
  @spec unregister(t(), String.t()) :: {:ok, t()} | {:error, :not_found}
  def unregister(%__MODULE__{} = registry, id) do
    if Map.has_key?(registry.subscriptions, id) do
      subscriptions = Map.delete(registry.subscriptions, id)
      {:ok, %{registry | subscriptions: subscriptions}}
    else
      {:error, :not_found}
    end
  end

  @doc """
  Looks up a subscription by its ID.

  ## Returns
    * `{:ok, subscription}` - Subscription was found
    * `{:error, :not_found}` - No subscription with this ID exists
  """
  @spec lookup(t(), String.t()) :: {:ok, Subscription.t()} | {:error, :not_found}
  def lookup(%__MODULE__{} = registry, id) do
    case Map.fetch(registry.subscriptions, id) do
      {:ok, subscription} -> {:ok, subscription}
      :error -> {:error, :not_found}
    end
  end

  @doc """
  Returns all subscriptions for a given path pattern.

  Finds all subscriptions that would match the given signal path.
  """
  @spec find_by_path(t(), String.t()) :: [Subscription.t()]
  def find_by_path(%__MODULE__{} = registry, path) when is_binary(path) do
    registry.subscriptions
    |> Map.values()
    |> Enum.filter(fn subscription ->
      Jido.Signal.Router.matches?(path, subscription.path)
    end)
  end

  @doc """
  Returns the count of subscriptions in the registry.
  """
  @spec count(t()) :: non_neg_integer()
  def count(%__MODULE__{} = registry) do
    map_size(registry.subscriptions)
  end

  @doc """
  Returns a list of all subscriptions in the registry.
  """
  @spec all(t()) :: [Subscription.t()]
  def all(%__MODULE__{} = registry) do
    Map.values(registry.subscriptions)
  end
end

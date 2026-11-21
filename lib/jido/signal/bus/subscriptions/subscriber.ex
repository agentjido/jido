defmodule Jido.Signal.Bus.Subscriptions.Subscriber do
  @moduledoc false

  alias Jido.Signal.Router

  @enforce_keys [:id, :path, :durable?, :cursor, :created_at]
  defstruct [
    :id,
    :path,
    :target,
    :monitor_ref,
    :in_flight,
    :created_at,
    durable?: false,
    cursor: 0
  ]

  @type t :: %__MODULE__{
          id: String.t(),
          path: String.t(),
          durable?: boolean(),
          target: pid() | nil,
          monitor_ref: reference() | nil,
          cursor: non_neg_integer(),
          in_flight: pos_integer() | nil,
          created_at: String.t()
        }

  @doc false
  @spec insert_subscriber(map(), t(), Router.match() | nil) :: map()
  def insert_subscriber(state, subscriber, match \\ nil) do
    route =
      case match do
        nil -> {subscriber.path, subscriber.id}
        match -> {subscriber.path, match, subscriber.id}
      end

    {:ok, router} = Router.add(state.router, route)

    %{
      state
      | subscriptions: Map.put(state.subscriptions, subscriber.id, subscriber),
        router: router
    }
  end

  @doc false
  @spec put_subscriber(map(), t()) :: map()
  def put_subscriber(state, subscriber) do
    %{state | subscriptions: Map.put(state.subscriptions, subscriber.id, subscriber)}
  end
end

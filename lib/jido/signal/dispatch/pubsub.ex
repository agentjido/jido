defmodule Jido.Signal.Dispatch.PubSub do
  @moduledoc """
  An adapter for dispatching signals through Phoenix.PubSub.

  This adapter implements the `Jido.Signal.Dispatch.Adapter` behaviour and provides
  functionality to broadcast signals through Phoenix.PubSub to all subscribers of a
  specific topic. It integrates with Phoenix's pub/sub system for distributed
  message broadcasting.

  ## Configuration Options

  * `:target` - (required) An atom specifying the PubSub server name
  * `:topic` - (required) A string specifying the topic to broadcast on

  ## Phoenix.PubSub Integration

  The adapter uses `Phoenix.PubSub.broadcast/3` to:
  * Broadcast signals to all subscribers of a topic
  * Handle distributed message delivery across nodes
  * Manage subscription-based message routing

  ## Examples

      # Basic usage
      config = {:pubsub, [
        target: :my_app_pubsub,
        topic: "events"
      ]}

      # Using with specific event topics
      config = {:pubsub, [
        target: :my_app_pubsub,
        topic: "user:123:events"
      ]}

  ## Error Handling

  The adapter handles these error conditions:

  * `:pubsub_not_found` - The target PubSub server is not running
  * Other errors from the Phoenix.PubSub system

  ## Notes

  * Ensure the PubSub server is started in your application supervision tree
  * Topics can be any string, but consider using consistent naming patterns
  * Messages are broadcast to all subscribers, so consider message volume
  """

  @behaviour Jido.Signal.Dispatch.Adapter

  @options_schema Zoi.keyword(
                    [
                      target:
                        Zoi.atom()
                        |> Zoi.refine({__MODULE__, :not_nil?, []})
                        |> Zoi.required(),
                      topic: Zoi.string() |> Zoi.required()
                    ],
                    unrecognized_keys: :error
                  )

  require Logger

  @type delivery_target :: atom()
  @type delivery_opts :: [
          target: delivery_target(),
          topic: String.t()
        ]
  @type delivery_error ::
          {:missing_dependency, :phoenix_pubsub}
          | :pubsub_not_found
          | term()

  @impl Jido.Signal.Dispatch.Adapter
  def options_schema, do: @options_schema

  @doc false
  def not_nil?(nil, _opts), do: {:error, "must not be nil"}
  def not_nil?(_value, _opts), do: :ok

  @impl Jido.Signal.Dispatch.Adapter
  @doc """
  Broadcasts a signal through Phoenix.PubSub.

  ## Parameters

  * `signal` - The signal to broadcast
  * `opts` - Options parsed by Dispatch

  ## Options

  * `:target` - (required) Atom identifying the PubSub server
  * `:topic` - (required) String topic to broadcast on

  ## Returns

  * `:ok` - Signal broadcast successfully
  * `{:error, {:missing_dependency, :phoenix_pubsub}}` - Phoenix.PubSub is not installed
  * `{:error, :pubsub_not_found}` - PubSub server not found
  * `{:error, reason}` - Other broadcast failure
  """
  @spec deliver(Jido.Signal.t(), delivery_opts()) ::
          :ok | {:error, delivery_error()}
  def deliver(signal, opts) do
    case ensure_phoenix_pubsub_loaded() do
      :ok ->
        do_deliver(signal, opts)

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp do_deliver(signal, opts) do
    target = Keyword.fetch!(opts, :target)
    topic = Keyword.fetch!(opts, :topic)

    try do
      apply(Phoenix.PubSub, :broadcast, [target, topic, signal])
    rescue
      ArgumentError -> {:error, :pubsub_not_found}
      MatchError -> {:error, :pubsub_not_found}
    catch
      :exit, {:noproc, _} -> {:error, :pubsub_not_found}
      :exit, reason -> {:error, reason}
    end
  end

  defp ensure_phoenix_pubsub_loaded do
    if Code.ensure_loaded?(Phoenix.PubSub) do
      :ok
    else
      Logger.warning(
        "Phoenix.PubSub is required for Jido.Signal.Dispatch.PubSub; " <>
          "add {:phoenix_pubsub, \"~> 2.1\"} to your dependencies to use :pubsub dispatch"
      )

      {:error, {:missing_dependency, :phoenix_pubsub}}
    end
  end
end

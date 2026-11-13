defmodule Jido.Examples.Signals.DeliveryGuarantees do
  @moduledoc "An explicit comparison of the delivery contracts proved in Chapter 8."

  @contracts [
    %{
      path: :agent_call,
      accepted_result: :turn_result,
      retained_for_replay: false,
      acknowledgement: :turn_completion,
      retry_owner: :caller,
      duplicate_rule: :application_idempotency
    },
    %{
      path: :pid_dispatch,
      accepted_result: :adapter_acceptance,
      retained_for_replay: false,
      acknowledgement: :none,
      retry_owner: :application,
      duplicate_rule: :application_idempotency
    },
    %{
      path: :pubsub_dispatch,
      accepted_result: :local_publication,
      retained_for_replay: false,
      acknowledgement: :none,
      retry_owner: :application,
      duplicate_rule: :application_idempotency
    },
    %{
      path: :bus_publish,
      accepted_result: :recorded_signal,
      retained_for_replay: true,
      acknowledgement: :optional,
      retry_owner: :subscriber,
      duplicate_rule: :cursor_and_domain_key
    },
    %{
      path: :durable_bus_subscription,
      accepted_result: :recorded_signal,
      retained_for_replay: true,
      acknowledgement: :explicit_cursor,
      retry_owner: :bus_and_subscriber,
      duplicate_rule: :cursor_and_domain_key
    }
  ]

  def all, do: @contracts

  def fetch(path) do
    case Enum.find(@contracts, &(&1.path == path)) do
      nil -> {:error, :unknown_delivery_path}
      contract -> {:ok, contract}
    end
  end
end

defmodule Jido.Examples.Operations.DeliveryPort do
  @moduledoc "The application port for one external delivery operation."

  @callback deliver(map()) :: {:ok, map()} | {:error, term()}
end

defmodule Jido.Examples.Operations.LocalDeliveryService do
  @moduledoc "A deterministic local implementation of the delivery port."

  @behaviour Jido.Examples.Operations.DeliveryPort

  @impl true
  def deliver(%{idempotency_key: key, payload: payload}) do
    {:ok, %{receipt_id: "local:#{key}", accepted_bytes: byte_size(JSON.encode!(payload))}}
  end
end

defmodule Jido.Examples.Operations.Deliver do
  @moduledoc "Calls the application-owned adapter from temporary execution context."

  alias Jido.Joi

  use Jido.Action,
    name: "operations_external_deliver",
    schema:
      Joi.object(
        %{
          idempotency_key: Joi.string(),
          payload: Joi.map()
        },
        unrecognized_keys: :error
      )

  @impl true
  def run(input, %{delivery_adapter: adapter}) when is_atom(adapter), do: adapter.deliver(input)
  def run(_input, _context), do: {:error, :delivery_adapter_not_configured}
end

defmodule Jido.Examples.Operations.ExternalDeliveryFlow do
  @moduledoc "Keeps the external adapter behind one normal application Flow."

  alias Jido.Joi

  use Jido.Flow,
    name: "operations_external_delivery_flow",
    schema:
      Joi.object(
        %{
          idempotency_key: Joi.string(),
          payload: Joi.map()
        },
        unrecognized_keys: :error
      )

  flow do
    step "deliver",
      action: Jido.Examples.Operations.Deliver,
      params: %{
        idempotency_key: input(:idempotency_key),
        payload: input(:payload)
      }

    output result("deliver")
  end
end

Code.require_file("external_adapter_boundary.ex", __DIR__)

defmodule Jido.Examples.Operations.ExternalAdapterBoundaryTest do
  use ExUnit.Case, async: true

  @moduletag :integration

  alias Jido.Examples.Operations.{ExternalDeliveryFlow, LocalDeliveryService}

  defmodule RejectedService do
    @behaviour Jido.Examples.Operations.DeliveryPort

    @impl true
    def deliver(_request), do: {:error, :offline_rejection}
  end

  test "the same Flow uses a deterministic local adapter" do
    input = %{idempotency_key: "delivery-7", payload: %{"message" => "hello"}}

    assert {:ok, %{receipt_id: "local:delivery-7", accepted_bytes: bytes}} =
             Jido.Exec.run(ExternalDeliveryFlow, input, %{delivery_adapter: LocalDeliveryService})

    assert bytes > 0
  end

  test "missing and failed adapters remain explicit Flow errors" do
    input = %{idempotency_key: "delivery-8", payload: %{}}

    assert {:error, _reason} = Jido.Exec.run(ExternalDeliveryFlow, input)

    assert {:error, _reason} =
             Jido.Exec.run(ExternalDeliveryFlow, input, %{delivery_adapter: RejectedService})
  end
end

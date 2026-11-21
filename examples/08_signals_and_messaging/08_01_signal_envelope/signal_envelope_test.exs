Code.require_file("signal_envelope.ex", __DIR__)

defmodule Jido.Examples.Signals.SignalEnvelopeTest do
  use ExUnit.Case, async: true
  @moduletag :integration

  alias Jido.Examples.Signals.SignalEnvelope.OrderSubmitted

  test "creates and round-trips one custom Signal envelope" do
    signal = OrderSubmitted.new!(%{"order_id" => "order-1", "total_cents" => 2_500})

    assert signal.specversion == "1.0"
    assert signal.type == "examples.orders.submitted"
    assert signal.source == "/examples/orders"
    assert Jido.Id.uuid7?(signal.id)

    assert {:ok, json} = Jido.Signal.Codec.serialize(signal, format: :json)
    assert {:ok, restored} = Jido.Signal.Codec.deserialize(json, format: :json)
    assert restored == signal
  end
end

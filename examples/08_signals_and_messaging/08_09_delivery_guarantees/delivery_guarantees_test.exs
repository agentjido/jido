Code.require_file("delivery_guarantees.ex", __DIR__)

defmodule Jido.Examples.Signals.DeliveryGuaranteesTest do
  use ExUnit.Case, async: true
  @moduletag :integration

  alias Jido.Examples.Signals.DeliveryGuarantees

  test "every supported path names its acknowledgement, retry, and duplicate boundary" do
    contracts = DeliveryGuarantees.all()
    assert Enum.map(contracts, & &1.path) |> Enum.uniq() |> length() == 5

    for contract <- contracts do
      assert contract.accepted_result
      assert is_boolean(contract.retained_for_replay)
      assert contract.acknowledgement
      assert contract.retry_owner
      assert contract.duplicate_rule
    end
  end

  test "only recorded Bus paths claim replay retention" do
    retained =
      DeliveryGuarantees.all()
      |> Enum.filter(& &1.retained_for_replay)
      |> Enum.map(& &1.path)

    assert retained == [:bus_publish, :durable_bus_subscription]
    assert {:error, :unknown_delivery_path} = DeliveryGuarantees.fetch(:exactly_once)
  end
end

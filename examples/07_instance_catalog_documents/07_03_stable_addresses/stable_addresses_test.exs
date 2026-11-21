Code.require_file("stable_addresses.ex", __DIR__)

defmodule Jido.Examples.StableAddressesTest do
  use ExUnit.Case, async: true
  @moduletag :integration

  alias Jido.Examples.StableAddresses

  setup do
    suffix = System.unique_integer([:positive])
    instance = :"stable_address_value_#{suffix}"
    namespace = "examples/stable-reference/#{suffix}"
    start_supervised!({Jido, name: instance, namespace: namespace}, id: instance)
    %{instance: instance, namespace: namespace}
  end

  test "a scoped Address has one exact versioned public form", c do
    assert {:ok, address} = StableAddresses.build(c.instance, "case-42", "tenant-a")
    assert {:ok, document} = StableAddresses.encode(address)

    assert document == %{
             "version" => 1,
             "namespace" => c.namespace,
             "partition" => "tenant-a",
             "id" => "case-42"
           }

    assert {:ok, ^address} = StableAddresses.decode(document)
  end

  test "unknown fields and empty identity values are rejected", c do
    assert {:ok, address} = StableAddresses.build(c.instance, "case-42", "tenant-a")
    document = Jido.Agent.Address.to_map!(address)

    assert {:error, %Jido.Error.ValidationError{}} =
             StableAddresses.decode(Map.put(document, "pid", inspect(self())))

    assert {:error, %Jido.Error.ValidationError{}} =
             StableAddresses.decode(%{document | "id" => ""})
  end
end

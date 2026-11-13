defmodule Jido.Agent.AddressTest do
  use ExUnit.Case, async: true

  alias Jido.Agent.Address
  alias Jido.Error.ValidationError

  test "schema and constructors return the same exact Address" do
    assert {:ok, Address} = Jido.Joi.Schema.struct_module(Address.schema())

    attrs = %{namespace: "shop/primary", partition: "west", id: "order-123"}

    assert {:ok, %Address{} = address} = Address.new(attrs)
    assert {:ok, ^address} = Address.new(Map.to_list(attrs))
    assert {:ok, ^address} = Address.new(address)
    assert {:ok, ^address} = Address.validate(address)
    assert Address.new!(attrs) == address

    assert Map.from_struct(address) == %{
             namespace: "shop/primary",
             partition: "west",
             id: "order-123"
           }
  end

  test "partition defaults to nil" do
    assert {:ok, %Address{namespace: "shop", partition: nil, id: "order-123"}} =
             Address.new(namespace: "shop", id: "order-123")
  end

  test "construction requires nonempty binary identity fields" do
    invalid_attrs = [
      %{},
      %{namespace: "shop"},
      %{id: "order-123"},
      %{namespace: "", id: "order-123"},
      %{namespace: "shop", id: ""},
      %{namespace: "shop", partition: "", id: "order-123"},
      %{namespace: :shop, id: "order-123"},
      %{namespace: "shop", partition: :west, id: "order-123"},
      %{namespace: "shop", id: 123}
    ]

    for attrs <- invalid_attrs do
      assert {:error, %ValidationError{kind: :input, subject: Address}} = Address.new(attrs)
    end
  end

  test "construction rejects unknown keys, serialized keys, and malformed input" do
    assert {:error, %ValidationError{}} =
             Address.new(namespace: "shop", id: "order-123", extra: true)

    assert {:error, %ValidationError{}} =
             Address.new(%{"namespace" => "shop", "id" => "order-123"})

    for value <- [[{"namespace", "shop"}], :invalid, nil, self()] do
      assert {:error, %ValidationError{}} = Address.new(value)
    end

    assert {:error, %ValidationError{}} = Address.validate(%{namespace: "shop", id: "order-123"})
  end

  test "validation rejects a changed invalid Address" do
    address = Address.new!(namespace: "shop", id: "order-123")

    assert {:error, %ValidationError{}} = Address.validate(%{address | namespace: ""})
    assert {:error, %ValidationError{}} = Address.validate(%{address | partition: ""})
    assert {:error, %ValidationError{}} = Address.validate(%{address | id: ""})

    assert {:error, %ValidationError{}} = Address.to_map(%{address | id: ""})
    assert {:error, %ValidationError{}} = Address.to_map(:invalid)

    assert_raise ValidationError, fn ->
      Address.to_map!(%{address | id: ""})
    end
  end

  test "bang constructors raise the validation error" do
    assert {:error, %ValidationError{} = new_error} = Address.new(namespace: "", id: "order-123")

    raised_new =
      assert_raise ValidationError, fn ->
        Address.new!(namespace: "", id: "order-123")
      end

    assert error_contract(raised_new) == error_contract(new_error)

    invalid_map = %{
      "version" => 2,
      "namespace" => "shop",
      "partition" => nil,
      "id" => "order-123"
    }

    assert {:error, %ValidationError{} = map_error} = Address.from_map(invalid_map)

    raised_map = assert_raise ValidationError, fn -> Address.from_map!(invalid_map) end
    assert error_contract(raised_map) == error_contract(map_error)
  end

  test "identity equality uses all fields and preserves exact content" do
    address = Address.new!(namespace: " Shop/Primary ", partition: "West/01", id: "Order-A")

    assert address.namespace == " Shop/Primary "
    assert address.partition == "West/01"
    assert address.id == "Order-A"

    assert address == Address.new!(namespace: " Shop/Primary ", partition: "West/01", id: "Order-A")
    refute address == Address.new!(namespace: "shop/primary", partition: "West/01", id: "Order-A")
    refute address == Address.new!(namespace: " Shop/Primary ", partition: "west/01", id: "Order-A")
    refute address == Address.new!(namespace: " Shop/Primary ", partition: "West/01", id: "order-a")
  end

  test "the version-1 map round trip preserves the exact Address" do
    for partition <- [nil, "west"] do
      address = Address.new!(namespace: "shop/primary", partition: partition, id: "order-123")

      encoded = %{
        "version" => 1,
        "namespace" => "shop/primary",
        "partition" => partition,
        "id" => "order-123"
      }

      assert {:ok, ^encoded} = Address.to_map(address)
      assert Address.to_map!(address) == encoded
      assert {:ok, ^address} = Address.from_map(encoded)
      assert Address.from_map!(encoded) == address
    end
  end

  test "the public map decoder is strict" do
    valid = %{
      "version" => 1,
      "namespace" => "shop",
      "partition" => nil,
      "id" => "order-123"
    }

    invalid_maps = [
      Map.delete(valid, "version"),
      Map.delete(valid, "namespace"),
      Map.delete(valid, "partition"),
      Map.delete(valid, "id"),
      Map.put(valid, "version", 2),
      Map.put(valid, "extra", true),
      Map.put(valid, "partition", ""),
      %{version: 1, namespace: "shop", partition: nil, id: "order-123"},
      Map.put(valid, :id, "mixed"),
      :invalid
    ]

    for value <- invalid_maps do
      assert {:error, %ValidationError{kind: :input, subject: Address}} = Address.from_map(value)
    end
  end

  test "the Address contains no runtime, code, activation, or storage fields" do
    address = Address.new!(namespace: "shop", id: "order-123")

    assert address |> Map.from_struct() |> Map.keys() |> Enum.sort() == [:id, :namespace, :partition]

    refute Map.has_key?(address, :module)
    refute Map.has_key?(address, :vsn)
    refute Map.has_key?(address, :pid)
    refute Map.has_key?(address, :node)
    refute Map.has_key?(address, :activation_id)
    refute Map.has_key?(address, :state_version)
    refute Map.has_key?(address, :storage_revision)
  end

  test "a process boundary does not change the Address" do
    address = Address.new!(namespace: "shop", partition: "west", id: "order-123")

    assert address == Task.async(fn -> address end) |> Task.await()
  end

  defp error_contract(error) do
    Map.take(error, [:message, :kind, :subject, :details, :class])
  end
end

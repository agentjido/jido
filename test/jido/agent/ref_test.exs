defmodule Jido.Agent.RefTest do
  use ExUnit.Case, async: true

  alias Jido.Agent.Ref
  alias Jido.Error.ValidationError

  test "schema and constructors return the same exact Ref" do
    assert %Zoi.Types.Struct{module: Ref} = Ref.schema()

    attrs = %{namespace: "shop/primary", partition: "west", id: "order-123"}

    assert {:ok, %Ref{} = ref} = Ref.new(attrs)
    assert {:ok, ^ref} = Ref.new(Map.to_list(attrs))
    assert {:ok, ^ref} = Ref.new(ref)
    assert {:ok, ^ref} = Ref.validate(ref)
    assert Ref.new!(attrs) == ref

    assert Map.from_struct(ref) == %{
             namespace: "shop/primary",
             partition: "west",
             id: "order-123"
           }
  end

  test "partition defaults to nil" do
    assert {:ok, %Ref{namespace: "shop", partition: nil, id: "order-123"}} =
             Ref.new(namespace: "shop", id: "order-123")
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
      assert {:error, %ValidationError{kind: :input, subject: Ref}} = Ref.new(attrs)
    end
  end

  test "construction rejects unknown keys, serialized keys, and malformed input" do
    assert {:error, %ValidationError{}} =
             Ref.new(namespace: "shop", id: "order-123", extra: true)

    assert {:error, %ValidationError{}} =
             Ref.new(%{"namespace" => "shop", "id" => "order-123"})

    for value <- [[{"namespace", "shop"}], :invalid, nil, self()] do
      assert {:error, %ValidationError{}} = Ref.new(value)
    end

    assert {:error, %ValidationError{}} = Ref.validate(%{namespace: "shop", id: "order-123"})
  end

  test "validation rejects a changed invalid Ref" do
    ref = Ref.new!(namespace: "shop", id: "order-123")

    assert {:error, %ValidationError{}} = Ref.validate(%{ref | namespace: ""})
    assert {:error, %ValidationError{}} = Ref.validate(%{ref | partition: ""})
    assert {:error, %ValidationError{}} = Ref.validate(%{ref | id: ""})

    assert_raise ValidationError, fn ->
      Ref.to_map(%{ref | id: ""})
    end
  end

  test "bang constructors raise the validation error" do
    assert {:error, %ValidationError{} = new_error} = Ref.new(namespace: "", id: "order-123")

    raised_new =
      assert_raise ValidationError, fn ->
        Ref.new!(namespace: "", id: "order-123")
      end

    assert error_contract(raised_new) == error_contract(new_error)

    invalid_map = %{
      "version" => 2,
      "namespace" => "shop",
      "partition" => nil,
      "id" => "order-123"
    }

    assert {:error, %ValidationError{} = map_error} = Ref.from_map(invalid_map)

    raised_map = assert_raise ValidationError, fn -> Ref.from_map!(invalid_map) end
    assert error_contract(raised_map) == error_contract(map_error)
  end

  test "identity equality uses all fields and preserves exact content" do
    ref = Ref.new!(namespace: " Shop/Primary ", partition: "West/01", id: "Order-A")

    assert ref.namespace == " Shop/Primary "
    assert ref.partition == "West/01"
    assert ref.id == "Order-A"

    assert ref == Ref.new!(namespace: " Shop/Primary ", partition: "West/01", id: "Order-A")
    refute ref == Ref.new!(namespace: "shop/primary", partition: "West/01", id: "Order-A")
    refute ref == Ref.new!(namespace: " Shop/Primary ", partition: "west/01", id: "Order-A")
    refute ref == Ref.new!(namespace: " Shop/Primary ", partition: "West/01", id: "order-a")
  end

  test "the version-1 map round trip preserves the exact Ref" do
    for partition <- [nil, "west"] do
      ref = Ref.new!(namespace: "shop/primary", partition: partition, id: "order-123")

      encoded = %{
        "version" => 1,
        "namespace" => "shop/primary",
        "partition" => partition,
        "id" => "order-123"
      }

      assert Ref.to_map(ref) == encoded
      assert {:ok, ^ref} = Ref.from_map(encoded)
      assert Ref.from_map!(encoded) == ref
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
      assert {:error, %ValidationError{kind: :input, subject: Ref}} = Ref.from_map(value)
    end
  end

  test "the Ref contains no runtime, code, activation, or storage fields" do
    ref = Ref.new!(namespace: "shop", id: "order-123")

    assert ref |> Map.from_struct() |> Map.keys() |> Enum.sort() == [:id, :namespace, :partition]

    refute Map.has_key?(ref, :module)
    refute Map.has_key?(ref, :vsn)
    refute Map.has_key?(ref, :pid)
    refute Map.has_key?(ref, :node)
    refute Map.has_key?(ref, :activation_id)
    refute Map.has_key?(ref, :state_version)
    refute Map.has_key?(ref, :storage_revision)
  end

  test "a process boundary does not change the Ref" do
    ref = Ref.new!(namespace: "shop", partition: "west", id: "order-123")

    assert ref == Task.async(fn -> ref end) |> Task.await()
  end

  defp error_contract(error) do
    Map.take(error, [:message, :kind, :subject, :details, :class])
  end
end

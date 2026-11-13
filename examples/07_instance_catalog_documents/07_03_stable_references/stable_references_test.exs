Code.require_file("stable_references.ex", __DIR__)

defmodule Jido.Examples.StableReferencesTest do
  use ExUnit.Case, async: true
  @moduletag :integration

  alias Jido.Examples.StableReferences

  setup do
    suffix = System.unique_integer([:positive])
    instance = :"stable_reference_value_#{suffix}"
    namespace = "examples/stable-reference/#{suffix}"
    start_supervised!({Jido, name: instance, namespace: namespace}, id: instance)
    %{instance: instance, namespace: namespace}
  end

  test "a scoped Ref has one exact versioned public form", c do
    assert {:ok, ref} = StableReferences.build(c.instance, "case-42", "tenant-a")
    assert {:ok, document} = StableReferences.encode(ref)

    assert document == %{
             "version" => 1,
             "namespace" => c.namespace,
             "partition" => "tenant-a",
             "id" => "case-42"
           }

    assert {:ok, ^ref} = StableReferences.decode(document)
  end

  test "unknown fields and empty identity values are rejected", c do
    assert {:ok, ref} = StableReferences.build(c.instance, "case-42", "tenant-a")
    document = Jido.Agent.Ref.to_map!(ref)

    assert {:error, %Jido.Error.ValidationError{}} =
             StableReferences.decode(Map.put(document, "pid", inspect(self())))

    assert {:error, %Jido.Error.ValidationError{}} =
             StableReferences.decode(%{document | "id" => ""})
  end
end

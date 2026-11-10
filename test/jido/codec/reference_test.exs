defmodule Jido.Codec.ReferenceTest do
  use ExUnit.Case, async: true

  alias Jido.Catalog
  alias Jido.Catalog.Error
  alias Jido.Codec.Reference

  defmodule Action do
  end

  setup do
    catalog =
      Catalog.from_targets!(__MODULE__, :jido, %{
        {"tests/action", 1} => {:action, Action}
      })

    %{catalog: catalog}
  end

  test "encodes and decodes exact typed references", %{catalog: catalog} do
    assert Reference.encode(catalog, :action, Action) ==
             {:ok, %{"id" => "tests/action", "vsn" => 1}}

    assert Reference.decode(
             catalog,
             %{"id" => "tests/action", "vsn" => 1},
             :action
           ) == {:ok, Action}
  end

  test "rejects malformed, unknown, and wrong-kind documents", %{catalog: catalog} do
    assert {:error, %Error{details: %{field: "extra"}}} =
             Reference.decode(
               catalog,
               %{"id" => "tests/action", "vsn" => 1, "extra" => true},
               :action
             )

    assert {:error, %Error{details: %{field: "id"}}} =
             Reference.decode(catalog, %{"vsn" => 1}, :action)

    assert {:error, %Error{details: %{actual: :action, expected: :flow}}} =
             Reference.decode(catalog, %{"id" => "tests/action", "vsn" => 1}, :flow)
  end
end

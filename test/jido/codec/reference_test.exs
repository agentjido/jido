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
        {"tests/action", 1} => Action
      })

    %{catalog: catalog}
  end

  test "encodes and decodes exact typed references", %{catalog: catalog} do
    assert Reference.encode(catalog, Action) ==
             {:ok, %{"id" => "tests/action", "vsn" => 1}}

    assert Reference.decode(catalog, %{"id" => "tests/action", "vsn" => 1}) == {:ok, Action}
  end

  test "rejects malformed references and leaves target roles to consumers", %{catalog: catalog} do
    assert {:error, %Error{details: %{field: "extra"}}} =
             Reference.decode(catalog, %{"id" => "tests/action", "vsn" => 1, "extra" => true})

    assert {:error, %Error{details: %{field: "id"}}} =
             Reference.decode(catalog, %{"vsn" => 1})

    assert {:ok, Action} =
             Reference.decode(catalog, %{"id" => "tests/action", "vsn" => 1})
  end
end

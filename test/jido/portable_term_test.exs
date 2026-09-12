defmodule Jido.PortableTermTest do
  use JidoTest.Case, async: true

  alias Jido.PortableTerm

  test "map validation reports the first invalid key or value with its exact path" do
    assert {:error, [:payload, {:map_key, 0}]} =
             PortableTerm.validate(%{self() => make_ref()}, :payload)

    assert {:error, [:payload, :first]} =
             PortableTerm.validate(%{second: self(), first: make_ref()}, :payload)

    assert {:error, [:payload, :second, 1]} =
             PortableTerm.validate(%{first: :ok, second: {:ok, self()}}, :payload)

    assert :ok = PortableTerm.validate(%{first: :ok, second: {:ok, [1, nil]}}, :payload)
  end
end

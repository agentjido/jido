defmodule Jido.Topology.ResourceTest do
  use JidoTest.Case, async: true

  alias Jido.Topology.Resource

  test "Bus is the only registered core resource kind" do
    assert Resource.kinds() == [:bus]
    assert Resource.resource?(%{kind: :bus})
    refute Resource.resource?(%{kind: :queue})
  end

  test "the resource boundary owns resource-specific option validation" do
    assert {:ok, [buffer_size: 10]} = Resource.validate(:bus, buffer_size: 10)

    assert {:error, error} = Resource.validate(:bus, name: :outside)
    assert error.message == "Topology owns Bus name, Registry, and Jido scope"

    assert {:error, error} = Resource.validate(:queue, [])
    assert error.message == "Unsupported topology option"
  end
end

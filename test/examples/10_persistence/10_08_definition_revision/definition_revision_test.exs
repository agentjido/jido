defmodule JidoTest.Examples.Persistence.DefinitionRevisionTest do
  use ExUnit.Case, async: true
  @moduletag :example
  alias Jido.Examples.DefinitionRevision, as: Example
  alias Jido.Persistence

  test "restore retains the saved definition, version, and complete state" do
    agent = %{Example.instantiate!(id: "cart", state: %{total: 20}) | vsn: 7}
    assert {:ok, saved} = Persistence.snapshot(agent)
    assert {:ok, ^agent} = Persistence.restore(saved)
    assert Example.definition().vsn == 1
  end

  test "a changed code reference requires an explicit upgrade" do
    agent = Example.instantiate!(id: "cart", state: %{total: 20})
    assert {:ok, saved} = Persistence.snapshot(agent)
    old = put_in(saved.references[Example.Add], <<0::128>>)
    assert {:error, %{code: :changed_reference}} = Persistence.restore(old)
    assert {:ok, upgraded} = Persistence.upgrade(old, Example.Upgrade)
    assert upgraded.vsn == 2
    assert upgraded.state == agent.state
    assert upgraded.id == agent.id
    assert upgraded.module == agent.module
    assert {:ok, current} = Persistence.snapshot(upgraded)
    assert {:ok, ^upgraded} = Persistence.restore(current)
  end
end

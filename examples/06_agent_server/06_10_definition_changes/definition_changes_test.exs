Code.require_file("definition_changes.ex", __DIR__)

defmodule Jido.Examples.Runtime.DefinitionChangesTest do
  use ExUnit.Case, async: false
  @moduletag :integration

  alias Jido.Agent.Address
  alias Jido.AgentServer.{Snapshot, TurnResult}
  alias Jido.Examples.DefinitionChanges, as: Example

  setup do
    id = System.unique_integer([:positive])
    instance = :"definition_upgrade_#{id}"
    namespace = "examples/definition-upgrade/#{id}"
    table = :"definition_upgrade_store_#{id}"

    start_supervised!(
      {Jido, name: instance, namespace: namespace, persistence: {Jido.Persistence.ETS, table: table}},
      id: instance
    )

    address = Address.new!(namespace: namespace, id: "document")
    agent = Example.V1.instantiate!(id: address.id, state: %{count: 2})
    {:ok, ^address} = Jido.create_agent(instance, address, agent)
    %{instance: instance, address: address}
  end

  test "an Instance-owned definition upgrade keeps the Address and replaces the activation", c do
    assert {:ok, first} = Jido.activate_agent(c.instance, c.address)

    assert {:ok, c.address} ==
             Jido.upgrade_agent(c.instance, c.address, Example.AdvanceVersion)

    assert {:ok, replacement} = Jido.activate_agent(c.instance, c.address)
    refute replacement == first

    assert %Snapshot{
             agent: %{module: Example.V1, vsn: 2, state: %{count: 2}},
             agent_revision: 1
           } = Jido.AgentServer.snapshot(replacement)

    assert {:ok, %TurnResult{status: :committed, agent_revision: 2}} =
             Jido.call(c.instance, c.address, Example.increment_signal())

    assert %{count: 3} == Jido.AgentServer.snapshot(replacement).agent.state
  end

  test "normal work changes state but not the definition" do
    agent = Example.V1.instantiate!(id: "fixed-definition")
    definition = Jido.Agent.definition(agent)

    assert {:ok, changed, []} = Jido.Agent.cmd(agent, Example.increment_signal())
    assert changed.state == %{count: 1}
    assert Jido.Agent.definition(changed) == definition
  end
end

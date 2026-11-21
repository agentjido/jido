defmodule Jido.Instance.OwnershipTransferTest do
  use ExUnit.Case, async: false
  use Covenant.Case, component: "jido.instance", async: false

  import Jido.Test.Eventually

  alias Jido.Agent.Address
  alias Jido.AgentOwnership
  alias Jido.AgentServer

  defmodule Increment do
    use Jido.Action,
      name: "ownership_transfer_increment",
      schema: Jido.Joi.object(%{amount: Jido.Joi.integer()})

    @impl true
    def run(%{amount: amount}, context) do
      case context do
        %{observer: observer, barrier: barrier} ->
          send(observer, {barrier, :started, self()})

          receive do
            {^barrier, :release} -> :ok
          after
            5_000 -> raise "ownership transfer test barrier was not released"
          end

        _other ->
          :ok
      end

      {:ok, %{count: context.agent_state.count + amount}}
    end
  end

  defmodule Counter do
    use Jido.Agent, name: "ownership_transfer_counter"

    state do
      schema Jido.Joi.object(%{count: Jido.Joi.integer() |> Jido.Joi.default(0)})
    end

    routes do
      route "ownership.transfer.increment", Increment
    end
  end

  defmodule TopologyOwner do
    use Jido.Agent, name: "ownership_transfer_topology_owner"

    topology do
      agent :child, Counter
    end
  end

  setup do
    suffix = System.unique_integer([:positive])
    instance = :"ownership_transfer_#{suffix}"
    namespace = "jido/test/ownership-transfer/#{suffix}"

    start_supervised!({Jido, name: instance, namespace: namespace}, id: instance)

    agents =
      Map.new(["owner-a", "owner-b", "child"], fn id ->
        address = Address.new!(namespace: namespace, id: id)
        assert {:ok, server} = Jido.start_agent(instance, Counter, id: id)
        assert :ok = AgentServer.await_ready(server)
        {id, %{address: address, server: server}}
      end)

    %{instance: instance, agents: agents}
  end

  @tag obligation: "jido.instance.I10"
  test "adoption and fenced transfer keep one process and one accepted Turn", c do
    child = c.agents["child"]
    owner_a = c.agents["owner-a"]
    owner_b = c.agents["owner-b"]
    child_address = child.address
    owner_a_address = owner_a.address
    owner_b_address = owner_b.address

    assert {:ok,
            %AgentOwnership{
              agent_address: ^child_address,
              owner_address: ^owner_a_address,
              request_id: "adopt-child"
            } = adopted} =
             Jido.transfer_agent_ownership(
               c.instance,
               child.address,
               owner_a.address,
               expected: nil,
               request_id: "adopt-child"
             )

    barrier = make_ref()
    observer = self()

    turn =
      Task.async(fn ->
        Jido.call(
          c.instance,
          child.address,
          Jido.Signal.new!("ownership.transfer.increment", %{amount: 2}, source: "/test/ownership"),
          context: %{observer: observer, barrier: barrier}
        )
      end)

    assert_receive {^barrier, :started, action}, 1_000

    assert {:ok,
            %AgentOwnership{
              agent_address: ^child_address,
              owner_address: ^owner_b_address,
              request_id: "move-child"
            } = transferred} =
             Jido.transfer_agent_ownership(
               c.instance,
               child.address,
               owner_b.address,
               expected: adopted,
               request_id: "move-child"
             )

    refute transferred.fence == adopted.fence
    assert {:ok, ^transferred} = Jido.agent_ownership(c.instance, child.address)

    assert {:ok, ^transferred} =
             Jido.transfer_agent_ownership(
               c.instance,
               child.address,
               owner_b.address,
               expected: adopted,
               request_id: "move-child"
             )

    assert {:error, :stale_ownership} =
             Jido.transfer_agent_ownership(
               c.instance,
               child.address,
               owner_a.address,
               expected: adopted,
               request_id: "stale-move"
             )

    send(action, {barrier, :release})
    assert {:ok, %{status: :committed}} = Task.await(turn)
    assert AgentServer.snapshot(child.server).agent.state.count == 2
    assert {:ok, same_server} = Jido.resolve_agent(c.instance, child.address)
    assert same_server == child.server
  end

  @tag obligation: "jido.instance.I10"
  test "ownership survives worker recovery and is released by activation replacement", c do
    child = c.agents["child"]
    owner = c.agents["owner-a"]

    assert {:ok, ownership} =
             Jido.transfer_agent_ownership(
               c.instance,
               child.address,
               owner.address,
               expected: nil,
               request_id: "adopt-for-recovery"
             )

    child_root = Jido.Test.AgentServer.Assertions.activation(child.server)
    Process.exit(child.server, :kill)

    assert_eventually(
      match?({:ok, pid} when is_pid(pid) and pid != child.server, Jido.resolve_agent(c.instance, child.address))
    )

    assert {:ok, recovered_child} = Jido.resolve_agent(c.instance, child.address)
    assert Jido.Test.AgentServer.Assertions.activation(recovered_child) == child_root
    assert {:ok, ^ownership} = Jido.agent_ownership(c.instance, child.address)

    Process.exit(owner.server, :kill)

    assert_eventually(
      match?({:ok, pid} when is_pid(pid) and pid != owner.server, Jido.resolve_agent(c.instance, owner.address))
    )

    assert Process.alive?(child_root)
    assert {:ok, ^ownership} = Jido.agent_ownership(c.instance, child.address)

    Process.exit(child_root, :kill)

    assert_eventually(
      match?({:ok, pid} when is_pid(pid) and pid != recovered_child, Jido.resolve_agent(c.instance, child.address))
    )

    assert {:ok, replacement} = Jido.resolve_agent(c.instance, child.address)
    refute Jido.Test.AgentServer.Assertions.activation(replacement) == child_root
    assert {:ok, nil} = Jido.agent_ownership(c.instance, child.address)

    assert {:error, :stale_ownership} =
             Jido.transfer_agent_ownership(
               c.instance,
               child.address,
               c.agents["owner-b"].address,
               expected: ownership,
               request_id: "stale-after-root-loss"
             )

    assert {:ok, next_ownership} =
             Jido.transfer_agent_ownership(
               c.instance,
               child.address,
               c.agents["owner-b"].address,
               expected: nil,
               request_id: "adopt-after-root-loss"
             )

    refute next_ownership.fence == ownership.fence
  end

  @tag obligation: "jido.instance.I10"
  test "the current owner activation controls shutdown and cycles are rejected", c do
    child = c.agents["child"]
    owner_a = c.agents["owner-a"]
    owner_b = c.agents["owner-b"]

    assert {:ok, adopted} =
             Jido.transfer_agent_ownership(
               c.instance,
               child.address,
               owner_a.address,
               expected: nil,
               request_id: "adopt-for-shutdown"
             )

    assert {:error, :ownership_cycle} =
             Jido.transfer_agent_ownership(
               c.instance,
               owner_a.address,
               child.address,
               expected: nil,
               request_id: "cycle"
             )

    assert {:ok, transferred} =
             Jido.transfer_agent_ownership(
               c.instance,
               child.address,
               owner_b.address,
               expected: adopted,
               request_id: "transfer-for-shutdown"
             )

    child_root = Jido.Test.AgentServer.Assertions.activation(child.server)
    child_monitor = Process.monitor(child_root)

    assert :ok = Jido.stop_agent(c.instance, owner_a.server)
    assert Process.alive?(child_root)
    assert {:ok, ^transferred} = Jido.agent_ownership(c.instance, child.address)

    assert :ok = Jido.stop_agent(c.instance, owner_b.server)
    assert_receive {:DOWN, ^child_monitor, :process, ^child_root, _reason}, 1_000
    assert {:error, :not_found} = Jido.resolve_agent(c.instance, child.address)
  end

  @tag obligation: "jido.instance.I10"
  test "static topology ownership cannot be transferred", c do
    assert {:ok, root} = Jido.start_agent(c.instance, TopologyOwner, id: "static-owner")
    assert :ok = AgentServer.await_ready(root)
    assert [child] = Jido.Test.AgentServer.TopologyAssertions.members(root)
    assert {:ok, child_address} = Jido.agent_address(c.instance, AgentServer.snapshot(child).agent.id)

    assert {:error, :ownership_not_transferable} =
             Jido.agent_ownership(c.instance, child_address)

    assert {:error, :ownership_not_transferable} =
             Jido.transfer_agent_ownership(
               c.instance,
               child_address,
               c.agents["owner-a"].address,
               expected: nil,
               request_id: "reject-static-child"
             )
  end
end

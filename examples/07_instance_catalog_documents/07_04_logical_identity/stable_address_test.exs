Code.require_file("stable_address.ex", __DIR__)

defmodule Jido.Examples.Runtime.StableAddressTest do
  use ExUnit.Case, async: true
  @moduletag :integration

  alias Jido.Agent.Address
  alias Jido.Examples.StableAddress

  setup do
    primary = :"address_primary_#{System.unique_integer([:positive])}"
    other = :"address_other_#{System.unique_integer([:positive])}"
    primary_namespace = "chat/primary/#{System.unique_integer([:positive])}"
    other_namespace = "chat/secondary/#{System.unique_integer([:positive])}"
    table = :"logical_identity_#{System.unique_integer([:positive])}"
    persistence = {Jido.Persistence.ETS, table: table}

    start_supervised!(
      {Jido, name: primary, namespace: primary_namespace, persistence: persistence},
      id: primary
    )

    start_supervised!(
      {Jido, name: other, namespace: other_namespace, persistence: persistence},
      id: other
    )

    address = Address.new!(namespace: primary_namespace, partition: "team-a", id: "conversation")

    %{
      persistence: persistence,
      primary: primary,
      other: other,
      address: address,
      other_namespace: other_namespace
    }
  end

  test "a saved Address survives persistent process replacement", c do
    first = create_and_activate(c.primary, c.address)

    assert :ok = Jido.AgentServer.await_ready(first)

    assert {:ok, %Jido.AgentServer.TurnResult{status: :committed}} =
             StableAddress.append(c.address, c.primary, "first")

    monitor = Process.monitor(first)
    Process.exit(first, :kill)
    assert_receive {:DOWN, ^monitor, :process, ^first, _reason}, 1_000

    replacement = await_replacement(c.primary, c.address, first, 100)

    assert replacement != first
    assert :ok = Jido.AgentServer.await_ready(replacement)

    assert {:ok, %Jido.AgentServer.TurnResult{status: :committed}} =
             StableAddress.append(c.address, c.primary, "second")

    assert Jido.AgentServer.snapshot(replacement).agent.state.messages == ["first", "second"]
  end

  test "equal IDs in separate namespaces reach separate conversations", c do
    other_address = %{c.address | namespace: c.other_namespace}

    _primary_server = create_and_activate(c.primary, c.address)
    _other_server = create_and_activate(c.other, other_address)

    assert {:ok, %Jido.AgentServer.TurnResult{status: :committed}} =
             StableAddress.append(c.address, c.primary, "A")

    assert {:ok, %Jido.AgentServer.TurnResult{status: :committed}} =
             StableAddress.append(other_address, c.other, "B")

    assert {:ok, first_server} = Jido.resolve_agent(c.primary, c.address)
    assert {:ok, second_server} = Jido.resolve_agent(c.other, other_address)
    assert Jido.AgentServer.snapshot(first_server).agent.state.messages == ["A"]
    assert Jido.AgentServer.snapshot(second_server).agent.state.messages == ["B"]
  end

  test "equal namespace and ID remain isolated by partition", c do
    other_partition = %{c.address | partition: "team-b"}

    _team_a_server = create_and_activate(c.primary, c.address)
    _team_b_server = create_and_activate(c.primary, other_partition)

    assert {:ok, %Jido.AgentServer.TurnResult{status: :committed}} =
             StableAddress.append(c.address, c.primary, "team A")

    assert {:ok, %Jido.AgentServer.TurnResult{status: :committed}} =
             StableAddress.append(other_partition, c.primary, "team B")

    assert {:ok, first_server} = Jido.resolve_agent(c.primary, c.address)
    assert {:ok, second_server} = Jido.resolve_agent(c.primary, other_partition)
    assert Jido.AgentServer.snapshot(first_server).agent.state.messages == ["team A"]
    assert Jido.AgentServer.snapshot(second_server).agent.state.messages == ["team B"]
  end

  test "an Address round trips through its exact versioned public map", c do
    assert {:ok, encoded} = Address.to_map(c.address)

    assert encoded == %{
             "version" => 1,
             "namespace" => c.address.namespace,
             "partition" => "team-a",
             "id" => "conversation"
           }

    assert {:ok, decoded} = Address.from_map(encoded)
    assert decoded == c.address
  end

  test "an Address survives rebinding its namespace to another local instance", c do
    first = create_and_activate(c.primary, c.address)

    assert :ok = Jido.AgentServer.await_ready(first)

    assert {:ok, %Jido.AgentServer.TurnResult{status: :committed}} =
             StableAddress.append(c.address, c.primary, "saved")

    assert {:ok, %Jido.AgentServer.Snapshot{}} = Jido.AgentServer.stop(first)
    refute Process.alive?(first)
    assert :ok = stop_supervised(c.primary)

    rebound = :"address_rebound_#{System.unique_integer([:positive])}"

    start_supervised!(
      {Jido, name: rebound, namespace: c.address.namespace, persistence: c.persistence},
      id: rebound
    )

    assert {:ok, rebound_server} = Jido.activate_agent(rebound, c.address)

    assert :ok = Jido.AgentServer.await_ready(rebound_server)

    assert {:ok, %Jido.AgentServer.TurnResult{status: :committed}} =
             StableAddress.append(c.address, rebound, "restored")

    assert Jido.AgentServer.snapshot(rebound_server).agent.state.messages == ["saved", "restored"]
  end

  defp create_and_activate(instance, address) do
    assert {:ok, ^address} = Jido.create_agent(instance, address, StableAddress)
    assert {:ok, server} = Jido.activate_agent(instance, address)
    assert :ok = Jido.AgentServer.await_ready(server)
    server
  end

  defp await_replacement(_instance, _address, _first, 0), do: nil

  defp await_replacement(instance, address, first, attempts) do
    case Jido.resolve_agent(instance, address) do
      {:ok, pid} when pid != first ->
        pid

      _result ->
        receive do
        after
          10 -> await_replacement(instance, address, first, attempts - 1)
        end
    end
  end
end

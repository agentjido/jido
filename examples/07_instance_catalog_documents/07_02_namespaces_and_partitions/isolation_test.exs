Code.require_file("isolation.ex", __DIR__)

defmodule Jido.Examples.InstanceIsolationTest do
  use ExUnit.Case, async: true
  @moduletag :integration

  alias Jido.AgentServer
  alias Jido.Examples.InstanceIsolation
  alias Jido.Examples.InstanceIsolation.Counter

  setup do
    suffix = System.unique_integer([:positive])
    first = :"isolation_first_#{suffix}"
    second = :"isolation_second_#{suffix}"
    first_namespace = "examples/isolation/first/#{suffix}"
    second_namespace = "examples/isolation/second/#{suffix}"

    first_store = {Jido.Persistence.ETS, table: :"isolation_first_store_#{suffix}"}
    second_store = {Jido.Persistence.ETS, table: :"isolation_second_store_#{suffix}"}

    start_supervised!(
      {Jido, name: first, namespace: first_namespace, persistence: first_store},
      id: first
    )

    start_supervised!(
      {Jido, name: second, namespace: second_namespace, persistence: second_store},
      id: second
    )

    %{first: first, second: second}
  end

  test "namespace and partition are both part of logical identity", c do
    assert {:ok, first_a} = InstanceIsolation.address(c.first, "counter", "team-a")
    assert {:ok, first_b} = InstanceIsolation.address(c.first, "counter", "team-b")
    assert {:ok, second_a} = InstanceIsolation.address(c.second, "counter", "team-a")

    for {instance, address} <- [{c.first, first_a}, {c.first, first_b}, {c.second, second_a}] do
      assert {:ok, ^address} = Jido.create_agent(instance, address, Counter)
      assert {:ok, server} = Jido.activate_agent(instance, address)
      assert :ok = AgentServer.await_ready(server)
    end

    assert {:ok, %{status: :committed}} = InstanceIsolation.increment(c.first, first_a)
    assert {:ok, %{status: :committed}} = InstanceIsolation.increment(c.first, first_a)
    assert {:ok, %{status: :committed}} = InstanceIsolation.increment(c.first, first_b)
    assert {:ok, %{status: :committed}} = InstanceIsolation.increment(c.second, second_a)

    assert count(c.first, first_a) == 2
    assert count(c.first, first_b) == 1
    assert count(c.second, second_a) == 1
  end

  test "an instance rejects an Address from another namespace", c do
    assert {:ok, foreign} = InstanceIsolation.address(c.second, "counter", "team-a")

    assert {:error, %Jido.Error.ValidationError{details: %{code: :jido_namespace_mismatch}}} =
             Jido.create_agent(c.first, foreign, Counter)
  end

  defp count(instance, address) do
    {:ok, server} = Jido.resolve_agent(instance, address)
    AgentServer.snapshot(server).agent.state.count
  end
end

Code.require_file("hibernate_and_thaw.ex", __DIR__)

defmodule Jido.Examples.Persistence.HibernateAndThawTest do
  use ExUnit.Case, async: false
  @moduletag :integration
  @moduletag group: :persistence

  alias Jido.Agent.Ref
  alias Jido.AgentServer.{Snapshot, Status, TurnResult}
  alias Jido.Examples.Persistence.HibernateAndThaw, as: Example

  setup do
    id = System.unique_integer([:positive])
    instance = :"passivation_#{id}"
    namespace = "examples/passivation/#{id}"
    table = :"passivation_store_#{id}"

    start_supervised!(
      {Jido,
       name: instance,
       namespace: namespace,
       persistence: {Jido.Persistence.ETS, table: table},
       activation: [idle_residency_timeout: 50]},
      id: instance
    )

    %{instance: instance, namespace: namespace}
  end

  test "a stopped activation restores the same durable Agent", c do
    ref = create(c, "counter")
    assert {:ok, first} = Jido.activate_agent(c.instance, ref)
    first_id = Jido.AgentServer.status(first).agent_activation_id

    {:ok, signal} = Example.increment_signal(%{amount: 4})

    assert {:ok,
            %TurnResult{
              status: :committed,
              agent_revision: 1,
              persistence_revision: 2
            }} = Jido.call(c.instance, ref, signal)

    assert {:ok, %Snapshot{agent: %{state: %{count: 4}}}} = Jido.AgentServer.stop(first)
    assert {:ok, restored} = Jido.activate_agent(c.instance, ref)
    refute Jido.AgentServer.status(restored).agent_activation_id == first_id

    assert %Snapshot{agent: %{state: %{count: 4}}, agent_revision: 1} =
             Jido.AgentServer.snapshot(restored)
  end

  test "idle passivation keeps the Ref alive and later delivery reactivates it", c do
    ref = create(c, "idle-counter")
    assert {:ok, first} = Jido.activate_agent(c.instance, ref)
    first_id = Jido.AgentServer.status(first).agent_activation_id

    eventually(fn -> match?(%Status{residency: :passivated}, Jido.status(c.instance, ref)) end)
    assert {:error, :not_found} = Jido.resolve_agent(c.instance, ref)

    {:ok, signal} = Example.increment_signal(%{amount: 1})
    assert {:ok, %TurnResult{status: :committed}} = Jido.call(c.instance, ref, signal)
    assert {:ok, second} = Jido.resolve_agent(c.instance, ref)
    refute Jido.AgentServer.status(second).agent_activation_id == first_id
    assert Jido.AgentServer.snapshot(second).agent.state.count == 1
  end

  test "activation rejects a missing durable record", c do
    missing = Ref.new!(namespace: c.namespace, id: "missing")
    assert {:error, :not_found} = Jido.activate_agent(c.instance, missing)
  end

  defp create(c, id) do
    ref = Ref.new!(namespace: c.namespace, id: id)
    {:ok, ^ref} = Jido.create_agent(c.instance, ref, Example)
    ref
  end

  defp eventually(fun, attempts \\ 200)
  defp eventually(fun, 0), do: flunk("condition did not become true: #{inspect(fun.())}")

  defp eventually(fun, attempts) do
    case fun.() do
      nil ->
        Process.sleep(10)
        eventually(fun, attempts - 1)

      false ->
        Process.sleep(10)
        eventually(fun, attempts - 1)

      value ->
        value
    end
  end
end

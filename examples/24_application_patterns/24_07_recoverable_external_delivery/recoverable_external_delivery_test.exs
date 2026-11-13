Code.require_file("../../12_persistence/12_07_recoverable_delivery/sink.ex", __DIR__)
Code.require_file("../../12_persistence/12_07_recoverable_delivery/support/memory_sink.ex", __DIR__)
Code.require_file("../../12_persistence/12_07_recoverable_delivery/delivery_plugin.ex", __DIR__)
Code.require_file("../../12_persistence/12_07_recoverable_delivery/delivery_worker.ex", __DIR__)
Code.require_file("../../12_persistence/12_07_recoverable_delivery/recoverable_delivery.ex", __DIR__)

defmodule Jido.Examples.Patterns.RecoverableExternalDeliveryTest do
  use ExUnit.Case, async: false
  @moduletag :integration

  alias Jido.AgentServer
  alias Jido.Examples.RecoverableDelivery, as: DeliveryAgent
  alias Jido.Examples.RecoverableDelivery.MemorySink

  test "saved intent recovers from process loss and an uncertain external outcome" do
    jido = start_persistent_jido()
    start_supervised!({MemorySink, jido: jido})
    {:ok, ref} = Jido.agent_ref(jido, "delivery-agent")
    {:ok, ^ref} = Jido.create_agent(jido, ref, DeliveryAgent)
    {:ok, server} = Jido.activate_agent(jido, ref)

    :ok = MemorySink.available(jido, :unavailable)

    assert {:ok, %AgentServer.TurnResult{status: :committed}} =
             Jido.call(
               jido,
               ref,
               DeliveryAgent.record_and_deliver_signal!(%{effect_id: "effect-1", value: 7})
             )

    assert AgentServer.snapshot(server).agent.state.delivery.pending == %{"effect-1" => 7}
    assert MemorySink.records(jido) == %{}

    assert :ok = Jido.stop_agent(jido, server)
    :ok = MemorySink.available(jido, :uncertain_once)
    {:ok, replacement} = Jido.activate_agent(jido, ref)

    assert :ok =
             wait_until(fn ->
               AgentServer.snapshot(replacement).agent.state.delivery == %{
                 pending: %{},
                 completed: %{"effect-1" => 7}
               }
             end)

    assert MemorySink.records(jido) == %{"effect-1" => 7}
    assert AgentServer.snapshot(replacement).agent_revision == 2
  end

  defp start_persistent_jido do
    suffix = System.unique_integer([:positive])
    name = :"recoverable_external_delivery_#{suffix}"
    persistence = {Jido.Persistence.ETS, table: Module.concat(__MODULE__, "Store#{suffix}")}

    start_supervised!(
      {Jido, name: name, namespace: "examples/recoverable-delivery/#{suffix}", persistence: persistence},
      id: name
    )

    name
  end

  defp wait_until(fun) do
    deadline = System.monotonic_time(:millisecond) + 2_000
    do_wait_until(fun, deadline)
  end

  defp do_wait_until(fun, deadline) do
    cond do
      fun.() ->
        :ok

      System.monotonic_time(:millisecond) >= deadline ->
        {:error, :timeout}

      true ->
        receive do
        after
          10 -> do_wait_until(fun, deadline)
        end
    end
  end
end

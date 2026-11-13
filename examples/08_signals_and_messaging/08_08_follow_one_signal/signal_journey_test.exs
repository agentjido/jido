Code.require_file("signal_journey.ex", __DIR__)

defmodule Jido.Examples.Signals.SignalJourneyTest do
  use ExUnit.Case, async: true
  @moduletag :integration

  alias Jido.Agent.Ref
  alias Jido.AgentServer
  alias Jido.Examples.Signals.SignalJourney
  alias Jido.Examples.Signals.SignalJourney.{Coordinator, Worker}
  alias Jido.Signal.Context

  setup do
    suffix = System.unique_integer([:positive])
    instance = :"signal_journey_#{suffix}"
    namespace = "examples/signal-journey/#{suffix}"
    store = {Jido.Persistence.ETS, table: :"signal_journey_store_#{suffix}"}
    start_supervised!({Jido, name: instance, namespace: namespace, persistence: store}, id: instance)

    coordinator = Ref.new!(namespace: namespace, id: "coordinator")
    worker = Ref.new!(namespace: namespace, id: "worker")

    for {ref, module} <- [{coordinator, Coordinator}, {worker, Worker}] do
      assert {:ok, ^ref} = Jido.create_agent(instance, ref, module)
      assert {:ok, server} = Jido.activate_agent(instance, ref)
      assert :ok = AgentServer.await_ready(server)
    end

    adapter = start_supervised!({Agent, fn -> 0 end})
    %{instance: instance, coordinator: coordinator, worker: worker, adapter: adapter}
  end

  test "one Signal keeps identity, trace, causation, and reply data across retry", c do
    assert {:ok, journey} =
             SignalJourney.run(c.instance, c.coordinator, c.worker, c.adapter, "request-7", 4)

    assert journey.injected_failure == {:error, :acknowledgement_lost}
    assert journey.delivery_attempts == 2

    assert journey.child_reply.data == %{
             request_id: "request-7",
             result: 8,
             reply_to: Ref.to_map!(c.coordinator),
             duplicate: true
           }

    assert journey.completed.data == %{request_id: "request-7", result: 8}

    signals = [journey.request, journey.planned, journey.child, journey.child_reply, journey.completed]
    assert Enum.all?(signals, &(Context.get(&1, "jidocorrelationid") == "request-7"))

    traces = Enum.map(signals, &Context.get_trace/1)
    assert traces |> Enum.map(& &1.trace_id) |> Enum.uniq() |> length() == 1
    assert Context.get_trace(journey.planned).causation_id == journey.request.id
    assert Context.get_trace(journey.child).causation_id == journey.planned.id
    assert Context.get_trace(journey.child_reply).causation_id == journey.child.id
    assert Context.get_trace(journey.completed).causation_id == journey.child_reply.id

    assert Enum.all?(Map.values(journey.turns), &is_binary(&1.turn_id))
    assert Enum.all?(Map.values(journey.turns), &(&1.status == :committed))

    {:ok, worker_server} = Jido.resolve_agent(c.instance, c.worker)
    assert AgentServer.snapshot(worker_server).agent.state.results == %{"request-7" => 8}
  end
end

Code.require_file("metrics.ex", __DIR__)

defmodule Jido.Examples.Observability.MetricsTest do
  use ExUnit.Case, async: true

  @moduletag :integration

  alias Jido.AgentServer
  alias Jido.Examples.Observability.Metrics.{Agent, Catalog, Reporter}

  test "the public metric catalog drives a local reporter" do
    count_metric =
      Enum.find(Catalog.entries(), fn metric ->
        metric.name == [:jido, :agent_server, :turn, :stop, :count]
      end)

    assert count_metric == %{
             event_name: [:jido, :agent_server, :turn, :stop],
             name: [:jido, :agent_server, :turn, :stop, :count],
             tags: [:status, :stage],
             unit: :unit
           }

    duration_metric =
      Enum.find(Catalog.entries(), fn metric ->
        metric.name == [:jido, :agent_server, :turn, :stop, :duration]
      end)

    assert duration_metric.unit == :millisecond
    owner = self()
    handler = {__MODULE__, make_ref()}

    assert :ok =
             :telemetry.attach(
               handler,
               count_metric.event_name,
               &Reporter.capture/4,
               owner
             )

    instance = :"metrics_example_#{System.unique_integer([:positive])}"

    try do
      start_supervised!({Jido, name: instance}, id: instance)
      id = "metrics-#{System.unique_integer([:positive])}"
      {:ok, server} = Jido.start_agent(instance, Agent, id: id)
      assert :ok = AgentServer.await_ready(server)
      assert {:ok, signal} = Agent.increment_signal(%{})
      assert {:ok, %AgentServer.TurnResult{status: :committed}} = AgentServer.call(server, signal)

      assert_receive {:metric_event, [:jido, :agent_server, :turn, :stop], measurements, metadata},
                     1_000

      assert is_integer(measurements.duration)
      assert metadata.status == :ok
      assert metadata.stage == :commit
      assert :ok = Jido.stop_agent(instance, server)
    after
      :telemetry.detach(handler)
    end
  end
end

Code.require_file("../support/event_probe.ex", __DIR__)
Code.require_file("safe_metadata.ex", __DIR__)

defmodule Jido.Examples.Observability.SafeMetadataTest do
  use ExUnit.Case, async: true

  @moduletag :integration

  alias Jido.AgentServer
  alias Jido.Examples.Observability.SafeMetadata.Agent
  alias Jido.Examples.Runtime.EventProbe

  test "semantic telemetry excludes Signal data and Agent state" do
    instance = :"safe_metadata_example_#{System.unique_integer([:positive])}"
    start_supervised!({Jido, name: instance}, id: instance)
    id = "safe-metadata-#{System.unique_integer([:positive])}"
    secret = "credential-value-that-must-not-be-exported"
    probe = EventProbe.attach(id)

    try do
      {:ok, server} = Jido.start_agent(instance, Agent, id: id)
      assert :ok = AgentServer.await_ready(server)
      assert {:ok, signal} = Agent.record_signal(%{secret: secret, value: 7})
      assert {:ok, %AgentServer.TurnResult{status: :committed}} = AgentServer.call(server, signal)

      events =
        eventually(fn ->
          values = EventProbe.events(probe)

          if Enum.any?(values, fn event ->
               event.event == [:jido, :agent_server, :turn, :settled]
             end) do
            values
          end
        end)

      assert AgentServer.snapshot(server).agent.state.secret == secret
      refute inspect(events) =~ secret
      refute Enum.any?(events, &Map.has_key?(&1.metadata, :signal_data))
      refute Enum.any?(events, &Map.has_key?(&1.metadata, :agent_state))

      assert Enum.any?(events, fn event ->
               event.event == [:jido, :agent_server, :turn, :settled] and
                 event.metadata.agent_id == id and
                 event.metadata.signal_id == signal.id
             end)

      assert :ok = Jido.stop_agent(instance, server)
    after
      EventProbe.detach(probe)
    end
  end

  defp eventually(fun, attempts \\ 100)
  defp eventually(_fun, 0), do: false

  defp eventually(fun, attempts) do
    case fun.() do
      value when value in [nil, false] ->
        receive do
        after
          10 -> eventually(fun, attempts - 1)
        end

      value ->
        value
    end
  end
end

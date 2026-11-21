Code.require_file("offline_tracer.ex", __DIR__)
Code.require_file("traced_agent.ex", __DIR__)

defmodule Jido.Examples.Observability.OpenTelemetryTest do
  use ExUnit.Case, async: false

  @moduletag :integration

  alias Jido.AgentServer
  alias Jido.Examples.Observability.OpenTelemetry.{Agent, OfflineTracer}

  setup do
    previous_tracer = :opentelemetry.get_tracer()
    previous_config = Application.fetch_env(:jido, :opentelemetry)
    previous_context = :otel_ctx.attach(:otel_ctx.new())

    assert :opentelemetry.set_default_tracer({OfflineTracer, self()})
    Application.put_env(:jido, :opentelemetry, enabled: true)

    on_exit(fn ->
      :otel_ctx.detach(previous_context)
      :opentelemetry.set_default_tracer(previous_tracer)

      case previous_config do
        {:ok, config} -> Application.put_env(:jido, :opentelemetry, config)
        :error -> Application.delete_env(:jido, :opentelemetry)
      end
    end)

    :ok
  end

  test "a host-managed tracer receives Jido spans without a network exporter" do
    assert Jido.Telemetry.open_telemetry?()

    instance = :"open_telemetry_example_#{System.unique_integer([:positive])}"
    start_supervised!({Jido, name: instance}, id: instance)
    id = "open-telemetry-#{System.unique_integer([:positive])}"
    {:ok, server} = Jido.start_agent(instance, Agent, id: id)
    assert :ok = AgentServer.await_ready(server)
    assert {:ok, signal} = Agent.record_signal(%{value: 7})
    assert {:ok, %AgentServer.TurnResult{status: :committed}} = AgentServer.call(server, signal)

    events = collect_events([])

    assert Enum.any?(events, fn
             {:span_started, "jido.agent_server.turn", options} ->
               options.attributes["jido.agent.id"] == id

             _other ->
               false
           end)

    assert Enum.any?(events, &match?({:span_ended, _timestamp}, &1))
    assert :ok = Jido.stop_agent(instance, server)
  end

  defp collect_events(events) do
    receive do
      event when elem(event, 0) in [:span_started, :span_attributes, :span_ended] ->
        collect_events([event | events])
    after
      50 -> Enum.reverse(events)
    end
  end
end

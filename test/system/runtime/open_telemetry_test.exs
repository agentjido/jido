Code.require_file("../support/case.exs", __DIR__)

defmodule JidoTest.System.OpenTelemetryTest do
  use JidoTest.System.Case, async: false
  require Record
  @moduletag :system
  @moduletag adapter: :ets
  alias Jido.AgentServer, as: Server
  alias JidoTest.System.{ControlledAgent, Observability}
  alias Jido.Tracing.Trace

  Record.defrecordp(:span, Record.extract(:span, from_lib: "opentelemetry/include/otel_span.hrl"))

  defmodule FailingExporter do
    @moduledoc false
    @behaviour :otel_exporter_traces
    def init(owner), do: {:ok, owner}

    def export(_table, _resource, owner) do
      send(owner, :export_attempted)
      raise "system exporter failure"
    end

    def shutdown(_owner), do: :ok
  end

  setup c do
    previous_tracer = :opentelemetry.get_tracer()
    previous_config = Application.fetch_env(:jido, :opentelemetry)
    limits_key = {:otel_span_limits, :span_limits}
    previous_limits = :persistent_term.get(limits_key, :missing)

    on_exit(fn ->
      :opentelemetry.set_default_tracer(previous_tracer)

      if previous_limits == :missing,
        do: :persistent_term.erase(limits_key),
        else: :persistent_term.put(limits_key, previous_limits)

      case previous_config do
        {:ok, value} -> Application.put_env(:jido, :opentelemetry, value)
        :error -> Application.delete_env(:jido, :opentelemetry)
      end
    end)

    exporter = if c[:exporter_failure], do: FailingExporter, else: :otel_exporter_pid

    config =
      :otel_configuration.merge_with_os([])
      |> Map.merge(%{
        sdk_disabled: false,
        resource_detectors: [],
        create_application_tracers: false,
        sampler: {:otel_sampler_always_on, %{}},
        processors: [
          {:otel_simple_processor, %{exporter: {exporter, self()}, exporting_timeout_ms: 5_000}}
        ]
      })

    :ok = :otel_span_limits.set(config)

    start_supervised!(%{
      id: :system_otel_sdk,
      start: {:opentelemetry_sup, :start_link, [config]},
      type: :supervisor
    })

    assert {:ok, _} = :otel_tracer_provider_sup.start(:system, :otel_resource.create([]), config)
    tracer = :otel_tracer_provider.get_tracer(:system, :system_test, :undefined, :undefined)
    assert :opentelemetry.set_default_tracer(tracer)
    witness = :otel_tracer.start_span(:otel_ctx.new(), tracer, "system.sdk.witness", %{})
    :otel_span.end_span(witness)
    Application.delete_env(:jido, :opentelemetry)
    assert Jido.Telemetry.open_telemetry?()
    :ok
  end

  test "exported SDK spans preserve Signal parentage through Turn, commit, and persistence", c do
    server = start_agent(c, module: ControlledAgent)
    trace = Trace.new_root()
    {:ok, signal} = Trace.put(ControlledAgent.signal(7, secret: "private-export-data"), trace)
    assert {:ok, saved} = Server.call(server, signal)
    stop_agent(c, server)
    spans = exports([])
    [turn] = Enum.filter(spans, &(&1.name == "jido.agent.turn"))
    [commit] = Enum.filter(spans, &(&1.name == "jido.agent.commit"))

    [write] =
      Enum.filter(
        spans,
        &(&1.name == "jido.persistence.compare_and_swap" and
            &1.attributes["jido.persistence.reason"] == "commit")
      )

    assert turn.trace_id == String.to_integer(trace.trace_id, 16)
    assert turn.parent_span_id == String.to_integer(trace.span_id, 16)
    assert commit.parent_span_id == turn.span_id
    assert write.parent_span_id == commit.span_id
    assert Enum.uniq(Enum.map([turn, commit, write], & &1.trace_id)) == [turn.trace_id]
    assert turn.attributes["jido.state.version.after"] == 1
    assert turn.attributes["jido.committed"] == true
    refute inspect(spans) =~ "private-export-data"
    assert {:ok, ^saved, 1} = load(c, saved.id, ControlledAgent)
    assert Enum.all?(spans, &(&1.end_time >= &1.start_time))
  end

  @tag exporter_failure: true
  test "an SDK exporter exception cannot change a committed result or stored revision", c do
    server = start_agent(c, module: ControlledAgent)
    assert {:ok, saved} = Server.call(server, ControlledAgent.signal(7))
    assert_receive :export_attempted, 5_000
    assert {:ok, ^saved, 1} = load(c, saved.id, ControlledAgent)
    stop_agent(c, server)
    Observability.assert_persistence(c.observer, :ok)
  end

  test "a failing Telemetry handler detaches without changing subsequent Turns", c do
    handler = {__MODULE__, make_ref()}

    :ok =
      :telemetry.attach(
        handler,
        [:jido, :agent, :turn, :stop],
        &__MODULE__.fail_handler/4,
        self()
      )

    on_exit(fn -> :telemetry.detach(handler) end)
    server = start_agent(c, module: ControlledAgent)
    assert {:ok, _} = Server.call(server, ControlledAgent.signal(7))
    assert_receive :handler_attempted, 5_000
    refute Enum.any?(:telemetry.list_handlers([]), &(&1.id == handler))
    assert {:ok, saved} = Server.call(server, ControlledAgent.signal(9))
    assert {:ok, ^saved, 2} = load(c, saved.id, ControlledAgent)
    stop_agent(c, server)
    turns = exports([]) |> Enum.filter(&(&1.name == "jido.agent.turn"))
    assert length(turns) == 2
  end

  def fail_handler(_event, _measurements, _metadata, owner) do
    send(owner, :handler_attempted)
    raise "system telemetry handler failure"
  end

  test "SDK overhead is measured without weakening state or resource checks", c do
    server = start_agent(c, module: ControlledAgent)

    samples =
      for enabled? <- [false, true, false, true] do
        Application.put_env(:jido, :opentelemetry, enabled: enabled?)

        {microseconds, _} =
          :timer.tc(fn ->
            for value <- 1..25,
                do: assert({:ok, _} = Server.call(server, ControlledAgent.signal(value)))
          end)

        {enabled?, microseconds}
      end

    assert Server.snapshot(server).state_version == 100
    assert {:ok, %{state: %{value: 25}}, 100} = load(c, Server.agent(server).id, ControlledAgent)
    assert %{postponed: 0, message_queue_len: 0} = Server.status(server).admission
    stop_agent(c, server)
    assert_empty_agent_pool(c)
    assert length(Enum.filter(exports([]), &(&1.name == "jido.agent.turn"))) == 50

    # Hardware and scheduler load affect these costs. Record measurements, not
    # an unstable timing ratio assertion. Both modes retain the system recorder.
    totals =
      Map.new(Enum.group_by(samples, &elem(&1, 0)), fn {mode, values} ->
        {mode, Enum.sum(Enum.map(values, &elem(&1, 1)))}
      end)

    Observability.measure(c.observer, %{
      sdk_off_50_turns_us: totals[false],
      sdk_on_50_turns_us: totals[true]
    })
  end

  defp exports(acc) do
    receive do
      {:span, record} ->
        entry = record |> span() |> Map.new()
        entry = Map.update!(entry, :attributes, &:otel_attributes.map/1)
        exports([entry | acc])
    after
      0 -> Enum.reverse(acc)
    end
  end
end

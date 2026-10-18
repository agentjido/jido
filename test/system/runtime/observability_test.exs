Code.require_file("../support/case.exs", __DIR__)
Code.require_file("../support/metrics.exs", __DIR__)

defmodule JidoTest.System.ObservabilityTest do
  use JidoTest.System.Case, async: false
  require Logger
  alias JidoTest.RecoverableDeliveryAgent, as: Probe
  alias JidoTest.System.Observability

  @moduletag :system
  @moduletag adapter: :ets

  setup c do
    server = start_agent(c)

    {:ok, route_signal_1} = Probe.record_and_deliver_signal(%{effect_id: "effect", value: 7})

    assert {:ok, _, _} =
             Jido.AgentServer.call(server, route_signal_1, [])

    completed(c, server, %{"effect" => 7})
    {:ok, server: server}
  end

  test "log waits observe a child process and retain events emitted before the wait", c do
    token = unique_id()
    task = Task.async(fn -> Logger.warning("system log witness", signal_id: token) end)
    :ok = Task.await(task)

    assert %{meta: %{signal_id: ^token}} =
             Observability.await_log(c.observer, &(&1.meta[:signal_id] == token))

    assert Observability.format_logs(c.observer) =~ "system log witness"
    stop_agent(c, c.server)
  end

  test "logs from another process group are not attributed to the scenario", c do
    token = unique_id()

    task =
      Task.async(fn ->
        Process.group_leader(self(), self())
        Logger.warning("foreign log witness", signal_id: token)
      end)

    :ok = Task.await(task)
    refute Enum.any?(Observability.logs(c.observer), &(&1.meta[:signal_id] == token))

    assert_raise ExUnit.AssertionError, ~r/Missing system logs event/, fn ->
      Observability.await_log(c.observer, &(&1.meta[:signal_id] == token), 0)
    end

    stop_agent(c, c.server)
  end

  test "public counters and a host revision gauge agree with committed state",
       c do
    alias Jido.AgentServer, as: Server
    alias JidoTest.System.{ControlledAgent, Metrics}
    turn_name = [:jido, :agent_server, :turn, :stop, :count]

    commit_name = [:jido, :agent_server, :commit, :count]
    start_name = [:jido, :agent_server, :lifecycle, :start, :count]
    stop_name = [:jido, :agent_server, :lifecycle, :stop, :count]

    counters =
      Jido.Telemetry.metrics()
      |> Enum.filter(&(&1.name in [turn_name, commit_name, start_name, stop_name]))

    assert length(counters) == 4

    gauge =
      Telemetry.Metrics.last_value("system.agent.revision",
        event_name: [:jido, :agent_server, :turn, :stop],
        measurement: :state_version_after
      )

    reporter = Metrics.start!(c.namespace, counters ++ [gauge])
    :ok = Jido.Debug.enable(c.jido, :verbose)
    on_exit(fn -> Jido.Debug.disable(c.jido) end)
    server = start_agent(c, module: ControlledAgent)
    secret = "private-signal-payload-#{unique_id()}"
    signal = ControlledAgent.signal(7, secret: secret)
    assert {:ok, saved, _} = Server.call(server, signal)

    assert {:error, _} =
             Server.call(server, ControlledAgent.signal(99, reject: true, secret: secret))

    assert Server.agent(server) == saved
    assert {:ok, ^saved, 1} = load(c, saved.id, ControlledAgent)

    stop_agent(c, server)

    assert Metrics.values(reporter) == %{
             {start_name, %{}} => 1,
             {stop_name, %{}} => 1,
             {commit_name, %{status: :ok}} => 1,
             {turn_name, %{status: :ok, stage: :commit}} => 1,
             {turn_name, %{status: :error, stage: :evaluate}} => 1,
             {[:system, :agent, :revision], %{}} => 1
           }

    stop_agent(c, c.server)
  end
end

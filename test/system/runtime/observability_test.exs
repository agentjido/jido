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
    assert {:ok, _} = Probe.record_and_deliver(server, "effect", 7)
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

  test "metric counters, a host revision gauge, and semantic logs agree with committed state",
       c do
    alias Jido.AgentServer, as: Server
    alias JidoTest.System.{ControlledAgent, Metrics}
    turn_name = [:jido, :agent, :turn, :stop, :count]
    counters = Enum.filter(Jido.Telemetry.metrics(), &(&1.name == turn_name))

    gauge =
      Telemetry.Metrics.last_value("system.agent.revision",
        event_name: [:jido, :agent, :turn, :stop],
        measurement: :state_version_after
      )

    reporter = Metrics.start!(c.namespace, counters ++ [gauge])
    :ok = Jido.Debug.enable(c.jido, :verbose)
    on_exit(fn -> Jido.Debug.disable(c.jido) end)
    server = start_agent(c, module: ControlledAgent)
    secret = "private-signal-payload-#{unique_id()}"
    signal = ControlledAgent.signal(7, secret: secret)
    assert {:ok, saved} = Server.call(server, signal)

    assert {:error, _} =
             Server.call(server, ControlledAgent.signal(99, reject: true, secret: secret))

    assert Server.agent(server) == saved
    assert {:ok, ^saved, 1} = load(c, saved.id, ControlledAgent)

    assert Metrics.values(reporter) == %{
             {turn_name, %{status: :ok, stage: :commit}} => 1,
             {turn_name, %{status: :error, stage: :evaluate}} => 1,
             {[:system, :agent, :revision], %{}} => 1
           }

    Observability.await_log(c.observer, fn log ->
      text = inspect(log.msg)
      String.contains?(text, "[jido.semantic]") and String.contains?(text, signal.id)
    end)

    logs = Enum.filter(Observability.logs(c.observer), &(inspect(&1.msg) =~ "[jido.semantic]"))
    assert logs != []
    refute inspect(logs) =~ secret
    stop_agent(c, server)
    stop_agent(c, c.server)
  end
end

Code.require_file("support/memory_provider.ex", __DIR__)
Code.require_file("external_uncertainty.ex", __DIR__)
Code.require_file("../support/durable_publication_probe.exs", __DIR__)

defmodule Jido.Examples.Durable.ExternalUncertaintyTest do
  use Jido.Test.Case, async: false
  @moduletag :integration

  @moduletag :tmp_dir
  alias Jido.Examples.Durable.ExternalUncertainty, as: Example
  alias Example.MemoryProvider
  alias Jido.Test.Examples.Durable.PublicationProbe

  setup c do
    provider = :"publication_#{System.unique_integer([:positive])}"
    start_supervised!({MemoryProvider, name: provider})
    start_supervised!({PublicationProbe, self()})
    persistence = {Jido.Persistence.File, path: c.tmp_dir}
    id = unique_id("publication")
    {:ok, server} = Jido.start_agent(c.jido, Example, id: id, persistence: persistence)
    assert :ok = Jido.AgentServer.await_ready(server)
    {:ok, provider: provider, server: server, id: id, persistence: persistence}
  end

  defp request(report \\ "Report: OTP", policy \\ :idempotent),
    do: Example.publish_signal(%{operation_id: "publish-1", report: report, policy: policy})

  test "recovery repeats the same operation ID after acceptance but publishes once", c do
    {:ok, signal} = request()

    pending =
      Jido.AgentServer.submit(c.server, signal, context: %{publication_provider: {PublicationProbe, c.provider}})

    assert_receive {:publication_accepted, action}, 5_000
    turn_id = Jido.AgentServer.status(c.server).active_turn_id
    assert MemoryProvider.records(c.provider) == %{"publish-1" => "Report: OTP"}
    monitor = Process.monitor(action)
    Process.exit(c.server, :kill)
    assert_receive {:DOWN, ^monitor, :process, ^action, _}, 5_000
    :ok = PublicationProbe.release()

    restored =
      eventually(fn ->
        case Jido.whereis_agent(c.jido, c.id) do
          pid when is_pid(pid) and pid != c.server -> pid
          _ -> nil
        end
      end)

    assert :ok = Jido.AgentServer.await_ready(restored)
    eventually(fn -> Jido.AgentServer.snapshot(restored).agent.state.status == :published end)

    assert %Jido.AgentServer.Status{work_state: :idle, active_turn_id: nil} =
             Jido.AgentServer.status(restored)

    assert is_binary(turn_id)
    assert MemoryProvider.attempts(c.provider) == 2
    assert MemoryProvider.records(c.provider) == %{"publish-1" => "Report: OTP"}
    assert {:error, _} = Jido.AgentServer.await(pending)

    state = Jido.AgentServer.snapshot(restored).agent
    {:ok, conflict} = request("different report")

    assert {:ok, %Jido.AgentServer.TurnResult{status: :failed, error: _}} =
             Jido.AgentServer.call(restored, conflict, context: %{publication_provider: {MemoryProvider, c.provider}})

    assert Jido.AgentServer.snapshot(restored).agent == state
    assert MemoryProvider.records(c.provider) == %{"publish-1" => "Report: OTP"}
    assert :ok = Jido.stop_agent(c.jido, restored)
    assert Jido.resident_agent_count(c.jido) == 0
  end

  test "cancellation cannot undo provider acceptance and does not replay it on restore", c do
    {:ok, signal} = request()

    pending =
      Jido.AgentServer.submit(c.server, signal, context: %{publication_provider: {PublicationProbe, c.provider}})

    assert_receive {:publication_accepted, action}, 5_000
    monitor = Process.monitor(action)
    assert %Jido.AgentServer.Status{active_turn_id: turn_id} = Jido.AgentServer.status(c.server)
    assert :ok = Jido.AgentServer.cancel_turn(c.server, turn_id)
    assert_receive {:DOWN, ^monitor, :process, ^action, _}, 5_000
    :ok = PublicationProbe.release()

    assert {:ok, %Jido.AgentServer.TurnResult{status: :cancelled}} =
             Jido.AgentServer.await(pending)

    assert Jido.AgentServer.snapshot(c.server).agent.state.status == :idle
    assert MemoryProvider.records(c.provider) == %{"publish-1" => "Report: OTP"}
    assert {:ok, %Jido.AgentServer.Snapshot{}} = Jido.AgentServer.stop(c.server)
    assert {:ok, awake} = Jido.thaw(c.jido, Example, c.id, persistence: c.persistence)
    assert :ok = Jido.AgentServer.await_ready(awake)

    assert %Jido.AgentServer.Status{work_state: :idle, active_turn_id: nil} =
             Jido.AgentServer.status(awake)

    assert MemoryProvider.attempts(c.provider) == 1
    assert :ok = Jido.stop_agent(c.jido, awake)
  end

  test "manual policy saves needs-attention without dispatching unsafe I/O", c do
    {:ok, signal} = request("Report: OTP", :manual)

    (
      assert {:ok, %Jido.AgentServer.TurnResult{} = turn_result} =
               Jido.AgentServer.call(c.server, signal)

      assert turn_result.status in [:committed, :waiting]
      agent = Jido.AgentServer.snapshot(c.server).agent
    )

    assert agent.state.status == :needs_attention
    assert MemoryProvider.records(c.provider) == %{}
    assert MemoryProvider.attempts(c.provider) == 0
    assert {:ok, %Jido.AgentServer.Snapshot{}} = Jido.AgentServer.stop(c.server)
    assert {:ok, awake} = Jido.thaw(c.jido, Example, c.id, persistence: c.persistence)
    assert :ok = Jido.AgentServer.await_ready(awake)
    assert Jido.AgentServer.snapshot(awake).agent == agent
    assert :ok = Jido.stop_agent(c.jido, awake)
  end
end

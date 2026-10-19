defmodule JidoTest.Examples.Durable.ExternalUncertaintyTest do
  use JidoTest.Case, async: false
  @moduletag :example
  @moduletag :tmp_dir

  alias Jido.AgentServer, as: Server
  alias Jido.Examples.Durable.ExternalUncertainty, as: Example
  alias Example.MemoryProvider
  alias JidoTest.Examples.Durable.PublicationProbe

  setup c do
    provider = :"publication_#{System.unique_integer([:positive])}"
    start_supervised!({MemoryProvider, name: provider})
    start_supervised!({PublicationProbe, self()})
    persistence = {Jido.Persistence.File, path: c.tmp_dir}
    id = unique_id("publication")
    {:ok, server} = Jido.start_agent(c.jido, Example, id: id, persistence: persistence)
    assert :ok = Server.await_ready(server)
    {:ok, provider: provider, server: server, id: id, persistence: persistence}
  end

  defp request(report \\ "Report: OTP", policy \\ :idempotent),
    do: Example.publish_signal(%{operation_id: "publish-1", report: report, policy: policy})

  test "recovery repeats the same operation ID after acceptance but publishes once", c do
    {:ok, signal} = request()

    pending =
      Server.submit(c.server, signal,
        context: %{publication_provider: {PublicationProbe, c.provider}}
      )

    assert_receive {:publication_accepted, action}, 5_000
    turn_id = Server.status(c.server).active.turn_id
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

    assert :ok = Server.await_ready(restored)
    eventually(fn -> Server.agent(restored).state.status == :published end)
    assert Server.status(restored).durable_turn == %{id: turn_id, status: :completed}
    assert MemoryProvider.attempts(c.provider) == 2
    assert MemoryProvider.records(c.provider) == %{"publish-1" => "Report: OTP"}
    assert {:error, _} = Server.await(pending)

    state = Server.agent(restored)
    {:ok, conflict} = request("different report")

    assert {:error, _} =
             Server.call(restored, conflict,
               context: %{publication_provider: {MemoryProvider, c.provider}}
             )

    assert Server.agent(restored) == state
    assert MemoryProvider.records(c.provider) == %{"publish-1" => "Report: OTP"}
    assert :ok = Jido.stop_agent(c.jido, restored)
    assert Jido.agent_count(c.jido) == 0
  end

  test "cancellation cannot undo provider acceptance and does not replay it on restore", c do
    {:ok, signal} = request()

    pending =
      Server.submit(c.server, signal,
        context: %{publication_provider: {PublicationProbe, c.provider}}
      )

    assert_receive {:publication_accepted, action}, 5_000
    monitor = Process.monitor(action)
    assert :ok = Server.cancel(c.server)
    assert_receive {:DOWN, ^monitor, :process, ^action, _}, 5_000
    :ok = PublicationProbe.release()
    assert {:error, _} = Server.await(pending)
    assert Server.agent(c.server).state.status == :idle
    assert MemoryProvider.records(c.provider) == %{"publish-1" => "Report: OTP"}
    assert :ok = Server.hibernate(c.server)
    assert {:ok, awake} = Jido.thaw(c.jido, Example, c.id, persistence: c.persistence)
    assert :ok = Server.await_ready(awake)
    assert Server.status(awake).durable_turn.status == :cancelled
    assert MemoryProvider.attempts(c.provider) == 1
    assert :ok = Jido.stop_agent(c.jido, awake)
  end

  test "manual policy saves needs-attention without dispatching unsafe I/O", c do
    {:ok, signal} = request("Report: OTP", :manual)
    assert {:ok, agent, []} = Server.call(c.server, signal)
    assert agent.state.status == :needs_attention
    assert MemoryProvider.records(c.provider) == %{}
    assert MemoryProvider.attempts(c.provider) == 0
    assert :ok = Server.hibernate(c.server)
    assert {:ok, awake} = Jido.thaw(c.jido, Example, c.id, persistence: c.persistence)
    assert :ok = Server.await_ready(awake)
    assert Server.agent(awake) == agent
    assert :ok = Jido.stop_agent(c.jido, awake)
  end
end

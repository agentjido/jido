Code.require_file("../support/case.exs", __DIR__)

defmodule JidoTest.System.Services.BedrockTransactions do
  use JidoTest.System.Case, async: false
  @moduletag :service
  @moduletag adapter: :bedrock
  @moduletag skip: "Bedrock service suite paused pending upstream fixes (bedrock-kv/bedrock#319)"
  alias Jido.AgentServer, as: Server
  alias JidoTest.RecoverableDeliveryAgent, as: Probe
  alias JidoTest.RecoverableDeliverySink, as: Sink
  alias JidoTest.System.Observability

  test "a real resolver abort retains the winning write and does not affect Agent checkpoints",
       c do
    {_, opts} = c.store
    repo = Keyword.fetch!(opts, :repo)
    owner = self()
    server = start_agent(c)
    assert {:ok, _} = Probe.record_and_deliver(server, "before-abort", 7)
    completed(c, server, %{"before-abort" => 7})
    snapshot = Server.snapshot(server)
    key = "system/transaction-conflict"

    held =
      Task.async(fn ->
        try do
          repo.transact(
            fn ->
              nil = repo.get(key)
              send(owner, {:transaction_read, self()})
              receive do: (:release -> :ok)
              repo.put(key, "stale")
            end,
            retry_limit: 0,
            timeout_in_ms: 10_000
          )
        rescue
          error -> {:error, Exception.message(error)}
        end
      end)

    assert_receive {:transaction_read, writer}, 10_000
    assert :ok = repo.transact(fn -> repo.put(key, "winner") end, retry_limit: 0)
    send(writer, :release)
    assert {:error, reason} = Task.await(held, 10_000)
    assert reason =~ ":aborted"
    assert "winner" == repo.transact(fn -> repo.get(key) end)
    assert {:ok, saved, 2} = load(c, snapshot.agent.id)
    assert saved == snapshot.agent
    assert Server.snapshot(server) == snapshot
    stop_agent(c, server)
    assert_empty_agent_pool(c)
    assert length(Sink.attempts(c.jido)) == 1

    Observability.service_log(c.observer, :bedrock, "Resolver rejected the stale transaction", %{
      status: :aborted
    })
  end

  test "a reply held after real log sync fences the Agent and restores its committed intent", c do
    {_, opts} = c.store
    repo = Keyword.fetch!(opts, :repo)
    sequencer = Process.whereis(repo.__cluster__().otp_name(:sequencer))
    assert is_pid(sequencer)

    server =
      start_agent(c,
        persistence: {Jido.Persistence.Bedrock, Keyword.put(opts, :timeout_in_ms, 200)}
      )

    id = Server.agent(server).id
    handler = {__MODULE__, make_ref()}

    :ok =
      :telemetry.attach(
        handler,
        [:bedrock, :sequencer, :successful_commit],
        &__MODULE__.hold_reply/4,
        {self(), sequencer}
      )

    on_exit(fn -> :telemetry.detach(handler) end)

    monitors = monitor_agent_tree(c, server)

    request =
      Server.send_request(
        server,
        Probe.record_and_deliver_signal!("lost-commit-reply", 19),
        :infinity
      )

    assert_receive {:commit_reply_held, ^sequencer, version}, 10_000
    assert is_binary(version)
    assert {:reply, {:error, _}} = Server.receive_response(request, 10_000)
    await_down(monitors)
    assert_empty_agent_pool(c)
    :telemetry.detach(handler)
    send(sequencer, :release_commit_reply)
    # The transaction caller is already gone. A real protocol request now
    # crosses the released Sequencer before checkpoint recovery proceeds.
    assert {:ok, pending, 1} = load(c, id)
    assert pending.state.delivery.pending == %{"lost-commit-reply" => 19}
    assert Sink.attempts(c.jido) == []
    restored = start_agent(c, id: id, restore: :required)
    completed(c, restored, %{"lost-commit-reply" => 19})
    assert {:ok, saved, 2} = load(c, id)
    assert saved == Server.agent(restored)
    stop_agent(c, restored)
    assert_empty_agent_pool(c)
    assert length(Sink.attempts(c.jido)) == 1

    Observability.service_log(
      c.observer,
      :bedrock,
      "Lost commit reply recovered from saved intent",
      %{revision: 2}
    )
  end

  def hold_reply(_event, _measures, %{commit_version: version}, {owner, sequencer}) do
    if self() == sequencer do
      monitor = Process.monitor(owner)
      send(owner, {:commit_reply_held, self(), version})

      receive do
        :release_commit_reply -> Process.demonitor(monitor, [:flush])
        {:DOWN, ^monitor, :process, ^owner, _} -> :ok
      end
    end
  end
end

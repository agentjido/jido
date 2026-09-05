defmodule JidoTest.Agent.EffectRecoveryTest do
  use JidoTest.Case, async: false
  @moduletag capability: "REC-01"

  alias Jido.AgentServer, as: Server
  alias Jido.Examples.RecoverableDelivery, as: Agent
  alias Jido.Examples.RecoverableDelivery.{Deliver, Output, Sink}

  defmodule FaultFile do
    @moduledoc false
    @behaviour Jido.Persistence.Adapter
    @impl true
    defdelegate get(key, opts), to: Jido.Persistence.File
    @impl true
    defdelegate put(key, value, opts), to: Jido.Persistence.File
    @impl true
    defdelegate delete(key, opts), to: Jido.Persistence.File

    @impl true
    def compare_and_swap(key, expected, value, opts) do
      if Elixir.Agent.get(Keyword.fetch!(opts, :fault), & &1) do
        {:error, :test_storage_unavailable}
      else
        Jido.Persistence.File.compare_and_swap(key, expected, value, opts)
      end
    end
  end

  setup %{jido: jido} do
    suffix = :crypto.strong_rand_bytes(12) |> Base.url_encode64(padding: false)
    path = Path.join(System.tmp_dir!(), "jido-effect-recovery-#{suffix}")
    on_exit(fn -> File.rm_rf!(path) end)
    start_supervised!({Sink, jido: jido, observer: self()})
    {:ok, persistence: {Jido.Persistence.File, path: path}}
  end

  test "pure evaluation adds business state and Plugin intent to one candidate" do
    agent = Agent.new!()

    assert {:ok, candidate, [%Deliver{effect_id: "effect-1", value: 7}]} =
             Agent.cmd(agent, Agent.record_and_deliver_signal!("effect-1", 7))

    assert agent.state.value == 0
    assert agent.state.delivery == %{pending: %{}, completed: %{}}
    assert candidate.state.value == 7
    assert candidate.state.delivery == %{pending: %{"effect-1" => 7}, completed: %{}}
  end

  test "confirmation validates the saved ID and value before completing work" do
    agent = Agent.new!()
    {:ok, pending, _} = Agent.cmd(agent, Agent.record_and_deliver_signal!("effect-1", 7))

    for {id, value} <- [{"unknown", 7}, {"effect-1", 99}] do
      assert {:error, _} = Agent.cmd(pending, Agent.confirm_delivery_signal!(id, value))
    end

    assert {:ok, completed, _} = Agent.cmd(pending, Agent.confirm_delivery_signal!("effect-1", 7))
    assert completed.state.delivery == %{pending: %{}, completed: %{"effect-1" => 7}}

    assert {:ok, ^completed, _} =
             Agent.cmd(completed, Agent.confirm_delivery_signal!("effect-1", 7))
  end

  test "completed IDs prevent duplicate delivery and conflicting state changes", context do
    server = start_agent(context)
    assert {:ok, _} = Agent.record_and_deliver(server, "effect-1", 7)
    assert_receive {:effect_attempt, "effect-1", _worker}, 1_000
    await_completed(server, %{"effect-1" => 7})
    assert Server.snapshot(server).state_version == 2
    assert {:ok, _} = Agent.record_and_deliver(server, "effect-1", 7)
    before_conflict = Server.snapshot(server)
    assert {:error, _} = Agent.record_and_deliver(server, "effect-1", 99)
    assert Server.snapshot(server) == before_conflict
    refute_receive {:effect_attempt, "effect-1", _worker}, 200
    assert Sink.records(context.jido) == %{"effect-1" => 7}

    assert {:error, :effect_identity_conflict} =
             Sink.deliver(context.jido, %Deliver{effect_id: "effect-1", value: 99})

    assert Sink.records(context.jido) == %{"effect-1" => 7}
  end

  for stage <- [:before_write, :after_write] do
    @stage stage
    test "restore resumes saved work after a crash at #{stage}", context do
      :ok = Sink.hold(context.jido, @stage)
      id = unique_id()
      server = start_agent(context, id: id)
      assert {:ok, committed} = Agent.record_and_deliver(server, "effect-1", 7)
      assert_receive {:effect_attempt, "effect-1", task}, 1_000
      expected = if @stage == :after_write, do: %{"effect-1" => 7}, else: %{}
      eventually(fn -> Sink.records(context.jido) == expected end)
      assert Server.snapshot(server) == %{agent: committed, state_version: 1}
      assert {:ok, ^committed, 1} = load(context, id)
      assert committed.state.delivery.pending == %{"effect-1" => 7}
      kill_agent(context, server, task, id)
      :ok = Sink.hold(context.jido, :none)
      restored = start_agent(context, id: id, restore: :required)
      assert_receive {:effect_attempt, "effect-1", _new_task}, 1_000
      await_completed(restored, %{"effect-1" => 7})
      assert Sink.records(context.jido) == %{"effect-1" => 7}
      assert %{agent: acknowledged, state_version: 2} = Server.snapshot(restored)
      assert acknowledged.state.value == 7
      assert {:ok, ^acknowledged, 2} = load(context, id)
    end
  end

  test "completed work remains complete after another Agent activation", context do
    id = unique_id()
    server = start_agent(context, id: id)
    assert {:ok, _} = Agent.record_and_deliver(server, "effect-1", 7)
    assert_receive {:effect_attempt, "effect-1", _task}, 1_000
    await_completed(server, %{"effect-1" => 7})
    committed = Server.snapshot(server)
    stop_monitor = Process.monitor(server)
    :ok = Jido.stop_agent(context.jido, server)
    assert_receive {:DOWN, ^stop_monitor, :process, ^server, _reason}, 1_000
    restored = start_agent(context, id: id, restore: :required)
    assert Server.snapshot(restored) == committed
    refute_receive {:effect_attempt, "effect-1", _task}, 250
  end

  test "Plugin loss restarts delivery without replacing the Agent", context do
    :ok = Sink.hold(context.jido, :before_write)
    server = start_agent(context)
    assert {:ok, _} = Agent.record_and_deliver(server, "effect-1", 7)
    assert_receive {:effect_attempt, "effect-1", task}, 1_000
    worker = Server.children(server)[{:plugin, Output}].pid
    worker_monitor = Process.monitor(worker)
    task_monitor = Process.monitor(task)
    :ok = Sink.hold(context.jido, :none)
    Process.exit(worker, :kill)
    assert_receive {:DOWN, ^worker_monitor, :process, ^worker, :killed}, 1_000
    assert_receive {:DOWN, ^task_monitor, :process, ^task, _reason}, 1_000
    assert_receive {:effect_attempt, "effect-1", replay_task}, 1_000
    assert replay_task != task
    await_completed(server, %{"effect-1" => 7})
    assert Process.alive?(server)
    assert Server.snapshot(server).state_version == 2
  end

  test "a blocked delivery permits new Turns and preserves older pending work", context do
    :ok = Sink.hold(context.jido, :before_write)
    server = start_agent(context)
    assert {:ok, _} = Agent.record_and_deliver(server, "effect-1", 7)
    assert_receive {:effect_attempt, "effect-1", task}, 1_000
    assert {:ok, latest} = Agent.record_and_deliver(server, "effect-2", 9)
    assert latest.state.value == 9
    assert latest.state.delivery.pending == %{"effect-1" => 7, "effect-2" => 9}
    assert Server.snapshot(server).state_version == 2
    assert {:ok, ^latest, 2} = load(context, latest.id)
    :ok = Sink.hold(context.jido, :none)
    send(task, :release)
    await_completed(server, %{"effect-1" => 7, "effect-2" => 9})
    assert Server.snapshot(server).state_version == 4
  end

  test "an unavailable sink is retried from saved intent", context do
    :ok = Sink.available(context.jido, false)
    server = start_agent(context)
    assert {:ok, _} = Agent.record_and_deliver(server, "effect-1", 7)
    assert_receive {:effect_attempt, "effect-1", first_task}, 1_000
    assert_receive {:effect_attempt, "effect-1", retry_task}, 1_000
    assert first_task != retry_task
    assert Server.agent(server).state.delivery.pending == %{"effect-1" => 7}
    assert Server.snapshot(server).state_version == 1
    :ok = Sink.available(context.jido, true)
    await_completed(server, %{"effect-1" => 7})
  end

  test "a failed intent write exposes no work to the live Plugin", context do
    {context, fault} = faulty_storage(context)
    server = start_agent(context)
    :ok = Elixir.Agent.update(fault, fn _ -> true end)
    before_write = Server.snapshot(server)

    assert {:error, {:persistence_failed, :test_storage_unavailable}} =
             Agent.record_and_deliver(server, "effect-1", 7)

    assert Server.snapshot(server) == before_write
    refute_receive {:effect_attempt, "effect-1", _task}, 200
    assert Sink.records(context.jido) == %{}
    assert {:error, :not_found} = load(context, before_write.agent.id)
  end

  test "a failed completion write retains intent and retries the same effect ID", context do
    {context, fault} = faulty_storage(context)
    :ok = Sink.hold(context.jido, :after_write)
    server = start_agent(context)
    assert {:ok, committed} = Agent.record_and_deliver(server, "effect-1", 7)
    assert_receive {:effect_attempt, "effect-1", task}, 1_000
    eventually(fn -> Sink.records(context.jido) == %{"effect-1" => 7} end)
    :ok = Elixir.Agent.update(fault, fn _ -> true end)
    :ok = Sink.hold(context.jido, :none)
    send(task, :release)

    assert_receive {:effect_attempt, "effect-1", retry_task}, 1_000
    assert retry_task != task
    assert Server.snapshot(server) == %{agent: committed, state_version: 1}
    assert {:ok, ^committed, 1} = load(context, committed.id)
    :ok = Elixir.Agent.update(fault, fn _ -> false end)
    await_completed(server, %{"effect-1" => 7})
    assert Sink.records(context.jido) == %{"effect-1" => 7}
    assert Server.snapshot(server).state_version == 2
  end

  defp faulty_storage(%{persistence: {_adapter, opts}} = context) do
    fault = start_supervised!({Elixir.Agent, fn -> false end})
    {%{context | persistence: {FaultFile, Keyword.put(opts, :fault, fault)}}, fault}
  end

  defp start_agent(context, opts \\ []) do
    opts =
      Keyword.merge(
        [id: unique_id(), persistence: context.persistence, restore: false, restart: :temporary],
        opts
      )

    {:ok, server} = Jido.start_agent(context.jido, Agent, opts)
    server
  end

  defp load(context, id),
    do:
      Jido.Persistence.load_agent_with_revision(context.persistence, Agent, id,
        instance: context.jido
      )

  defp await_completed(server, records) do
    eventually(fn ->
      Server.agent(server).state.delivery == %{pending: %{}, completed: records}
    end)
  end

  defp kill_agent(context, server, task, id) do
    agent_monitor = Process.monitor(server)
    task_monitor = Process.monitor(task)
    Process.exit(server, :kill)
    assert_receive {:DOWN, ^agent_monitor, :process, ^server, :killed}, 1_000
    assert_receive {:DOWN, ^task_monitor, :process, ^task, _reason}, 1_000
    eventually(fn -> Jido.whereis_agent(context.jido, id) == nil end)
  end
end

defmodule JidoTest.System.TurnModel do
  @moduledoc false
  import ExUnit.Assertions
  import JidoTest.System.Case
  alias Jido.AgentServer, as: Server
  alias Jido.Persistence
  alias JidoTest.System.{ControlledAgent, FaultAdapter, Observability}

  @operations [
    :success,
    :reject,
    :cancel,
    :timeout,
    :restart,
    :conflict,
    :delete,
    :reject_write,
    :lost_reply
  ]

  def commands(seed, rounds \\ 2) do
    state = :rand.seed_s(:exsss, {seed, seed + 1, seed + 2})

    {commands, _state} =
      Enum.map_reduce(1..rounds, state, fn _, state ->
        {items, state} =
          Enum.map_reduce(@operations, state, fn op, state ->
            {order, state} = :rand.uniform_s(state)
            {value, state} = :rand.uniform_s(1_000, state)
            {{order, %{op: op, value: value}}, state}
          end)

        {items |> Enum.sort() |> Enum.map(&elem(&1, 1)), state}
      end)

    [%{op: :success, value: 1} | List.flatten(commands)]
  end

  # The oracle uses only command data. It never reads a live Agent or stored
  # checkpoint to decide the expected next state.
  def next(model, %{op: op, value: value})
      when op in [:success, :conflict, :lost_reply],
      do: %{model | value: value, revision: model.revision + 1}

  def next(model, %{op: :delete}), do: %{value: 0, revision: 0, epoch: model.epoch + 1}
  def next(model, _command), do: model

  def verify(c, seed, rounds \\ 2) do
    commands = commands(seed, rounds)
    before = resources(c)

    case run(c, commands) do
      :ok ->
        after_run = resources(c)
        assert after_run.processes <= before.processes + 20
        assert after_run.memory <= before.memory + 64_000_000 + length(commands) * 100_000
        expected_records = Enum.count(commands, &(&1.op == :delete)) + 1
        assert after_run.records - before.records == expected_records
        assert after_run.storage_bytes - before.storage_bytes <= expected_records * 16_384

        Observability.measure(c.observer, %{
          model_commands: length(commands),
          model_rounds: rounds,
          processes_before: before.processes,
          processes_after: after_run.processes,
          memory_before_bytes: before.memory,
          memory_after_bytes: after_run.memory,
          storage_records: after_run.records,
          storage_bytes: after_run.storage_bytes
        })

        :ok

      {:error, error, stack} ->
        signature = failure_signature(error, stack)
        path = Path.join(c.tmp_dir, "turn-model-failure.json")
        # Keep the original replay even if a later reduction is interrupted.
        File.write!(
          path,
          Jason.encode!(%{seed: seed, commands: commands, replay: commands, reduced: false})
        )

        # Remove one command at a time, replaying from a fresh identity. Bound
        # the replay budget; the artifact states whether reduction completed.
        {minimal, complete?} =
          shrink(commands, fn candidate ->
            case run(c, candidate) do
              {:error, reduced_error, reduced_stack} ->
                failure_signature(reduced_error, reduced_stack) == signature

              :ok ->
                false
            end
          end)

        File.write!(
          path,
          Jason.encode!(%{seed: seed, commands: commands, replay: minimal, reduced: complete?})
        )

        reraise ExUnit.AssertionError,
                [message: "#{Exception.message(error)}\nReplay artifact: #{path}"],
                stack
    end
  end

  def shrink(commands, fails?, budget \\ 40), do: reduce(commands, fails?, 0, budget)

  defp failure_signature(error, [{module, function, _arity, location} | _]),
    do: {error.__struct__, module, function, location[:file], location[:line]}

  defp reduce(commands, _fails?, index, _budget) when index >= length(commands),
    do: {commands, true}

  defp reduce(commands, _fails?, _index, 0), do: {commands, false}

  defp reduce(commands, fails?, index, budget) do
    candidate = List.delete_at(commands, index)

    if candidate != [] and fails?.(candidate),
      do: reduce(candidate, fails?, 0, budget - 1),
      else: reduce(commands, fails?, index + 1, budget - 1)
  end

  defp run(c, commands) do
    base = "model-#{System.unique_integer([:positive])}"
    FaultAdapter.sequence(c.control, [])
    model = %{value: 0, revision: 0, epoch: 0}
    server = activate(c, base, model, false)

    try do
      {server, _model} =
        Enum.reduce(commands, {server, model}, fn command, {server, model} ->
          expected = next(model, command)
          server = execute(c, base, server, model, expected, command)
          snapshot = Server.snapshot(server)
          assert snapshot.agent.state == %{value: expected.value}
          assert snapshot.state_version == expected.revision
          assert {:ok, stored, revision} = load(c, snapshot.agent.id, ControlledAgent)
          assert {stored.state, revision} == {%{value: expected.value}, expected.revision}
          assert Server.status(server).admission.postponed == 0
          assert Process.info(server, :message_queue_len) == {:message_queue_len, 0}
          {server, expected}
        end)

      stop_agent(c, server)
      assert_empty_agent_pool(c)
      assert JidoTest.RecoverableDeliverySink.attempts(c.jido) == []
      :ok
    rescue
      error -> {:error, error, __STACKTRACE__}
    after
      # All model Agents belong to this isolated pool. Clear it even after an
      # assertion fails, before a shrink replay starts under a new identity.
      pool = Jido.agent_supervisor_name(c.jido)

      for {_, pid, _, _} <- DynamicSupervisor.which_children(pool),
          is_pid(pid),
          do: DynamicSupervisor.terminate_child(pool, pid)

      FaultAdapter.sequence(c.control, [])
    end
  end

  defp resources(c) do
    :erlang.garbage_collect()
    {records, bytes} = storage_size(c.store)

    %{
      processes: :erlang.system_info(:process_count),
      memory: :erlang.memory(:total),
      records: records,
      storage_bytes: bytes
    }
  end

  defp storage_size({Jido.Persistence.ETS, opts}) do
    rows = :ets.tab2list(:"#{Keyword.fetch!(opts, :table)}_records")
    {length(rows), Enum.sum(for {_key, value} <- rows, do: byte_size(value))}
  end

  defp storage_size({Jido.Persistence.File, opts}) do
    files =
      Path.wildcard(Path.join([Keyword.fetch!(opts, :path), "records", "*"]))
      |> Enum.filter(&File.regular?/1)

    {length(files), Enum.sum(for file <- files, do: File.stat!(file).size)}
  end

  defp storage_size({Jido.Persistence.Ecto, opts}) do
    %{rows: [[records, bytes]]} =
      Ecto.Adapters.SQL.query!(
        Keyword.fetch!(opts, :repo),
        "SELECT count(*), coalesce(sum(length(value)), 0) FROM jido_persistence_records",
        []
      )

    {records, bytes}
  end

  defp execute(_c, _base, server, _model, _expected, %{op: :success, value: value}) do
    assert {:ok, _} = Server.call(server, ControlledAgent.signal(value))
    server
  end

  defp execute(_c, _base, server, _model, _expected, %{op: :reject, value: value}) do
    assert {:error, _} = Server.call(server, ControlledAgent.signal(value, reject: true))
    server
  end

  defp execute(c, _base, server, _model, _expected, %{op: op, value: value})
       when op in [:cancel, :timeout] do
    gate = make_ref()
    signal = ControlledAgent.signal(value, gate: gate, observer: self())
    request = Server.send_request(server, signal, :infinity)
    assert_receive {:work_held, ^gate, worker}, 10_000
    monitor = Process.monitor(worker)

    {_, _, _, started} =
      Observability.await(c.observer, fn
        {^server, [:jido, :agent, :turn, :start], _, %{source_signal_id: source}} ->
          source == signal.id

        _ ->
          false
      end)

    if op == :cancel do
      assert :ok = Server.cancel_turn(server, started.turn_id)
      assert {:reply, {:error, :cancelled}} = Server.receive_response(request, 10_000)
    else
      assert {:reply, {:error, %Jido.Error.TimeoutError{}}} =
               Server.receive_response(request, 10_000)
    end

    assert_receive {:DOWN, ^monitor, :process, ^worker, _}, 10_000
    server
  end

  defp execute(c, base, server, _model, expected, %{op: :restart}) do
    kill_agent(c, server)
    activate(c, base, expected, :required)
  end

  defp execute(c, base, server, model, expected, %{op: :conflict, value: value}) do
    agent = Server.agent(server)
    candidate = %{agent | state: %{value: value}}

    assert :ok =
             Persistence.save_agent(c.store, candidate,
               instance: c.jido,
               namespace: c.namespace,
               expected_revision: model.revision,
               revision: expected.revision
             )

    fenced(c, server, ControlledAgent.signal(-1), :conflict)
    activate(c, base, expected, :required)
  end

  defp execute(c, base, server, _model, expected, %{op: :delete}) do
    id = Server.agent(server).id

    assert :ok =
             Persistence.delete_agent(c.store, ControlledAgent, id,
               instance: c.jido,
               namespace: c.namespace
             )

    fenced(c, server, ControlledAgent.signal(-1), :conflict)
    assert {:error, :deleted} = load(c, id, ControlledAgent)
    activate(c, base, expected, false)
  end

  defp execute(c, base, server, model, expected, %{op: op, value: value})
       when op in [:reject_write, :lost_reply] do
    {fault, reason} =
      if op == :reject_write,
        do: {:reject, {:rejected, :system_fault}},
        else: {:lost_reply, {:indeterminate, :system_lost_reply}}

    FaultAdapter.arm(c.control, {model.revision + 1, fault})
    fenced(c, server, ControlledAgent.signal(value), reason)
    activate(c, base, expected, :required)
  end

  defp fenced(c, server, signal, reason) do
    monitors = monitor_agent_tree(c, server)
    assert {:error, {:persistence_failed, ^reason}} = Server.call(server, signal)
    await_down(monitors)
    assert_empty_agent_pool(c)
    Observability.assert_turn(c.observer, signal, :error, false)
  end

  defp activate(c, base, model, restore) do
    start_agent(c,
      module: ControlledAgent,
      id: "#{base}-#{model.epoch}",
      restore: restore,
      turn_timeout: 100
    )
  end
end

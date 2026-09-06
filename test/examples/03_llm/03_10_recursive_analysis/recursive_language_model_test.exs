defmodule JidoTest.Examples.LLM.RecursiveLanguageModelTest do
  use JidoTest.AgentCase

  @moduletag group: :llm
  @moduletag complexity: 3

  alias Jido.Action.Error
  alias Jido.AgentServer, as: Server
  alias Jido.Examples.RecursiveLanguageModel, as: RLM
  alias Jido.Examples.RecursiveLanguageModel.{Corpus, Fixtures, ScriptedModel}

  defmodule BarrierModel do
    @behaviour Jido.Examples.RecursiveLanguageModel.Model

    @impl true
    def complete({owner, model}, request) do
      response = ScriptedModel.complete(model, request)

      if request.stage == :read and request.range.offset == 0 do
        send(owner, {:rlm_waiting, self(), request})

        receive do
          :release_rlm -> response
        end
      else
        response
      end
    end
  end

  defmodule BrokenStore do
    @behaviour Jido.Examples.RecursiveLanguageModel.Store

    @impl true
    def describe(_client, _id), do: {:ok, %{records: 1, bytes: 1_000}}

    @impl true
    def read(response, _id, _range, _allowance), do: response
  end

  defmodule RaisingModel do
    @behaviour Jido.Examples.RecursiveLanguageModel.Model

    @impl true
    def complete(_client, _request), do: raise("provider failed")
  end

  setup %{jido: jido} do
    rows = Fixtures.logs(17)
    store = store(%{"logs-v1" => rows, "empty" => []})
    model = model(chunk_size: 4)
    agent = agent(jido)
    %{rows: rows, store: store, model: model, agent: agent}
  end

  test "direct evaluation and Server execution agree and commit only the complete result", ctx do
    before = Server.snapshot(ctx.agent)
    signal = RLM.analyze_signal!("logs-v1")
    context = clients(ctx)

    assert {:ok, candidate, []} = RLM.cmd(before.agent, signal, context: context)
    assert Server.snapshot(ctx.agent) == before
    assert {:ok, ^candidate} = Server.call(ctx.agent, signal, context: context)
    assert Server.snapshot(ctx.agent) == %{agent: candidate, state_version: 1}
    assert candidate.state.counts == oracle(ctx.rows)
    assert candidate.state.turns == 1
    assert candidate.state.usage.records_read == 17
    assert candidate.state.usage.peak_read_records <= 4
    assert_tree(candidate.state, 17)

    refute Map.has_key?(signal.data, :model)
    refute Map.has_key?(signal.data, :store)
    refute Map.has_key?(candidate.state, :model)
    refute Map.has_key?(candidate.state, :store)
    refute inspect(candidate.state) =~ String.duplicate("x", 64)
    assert Enum.all?(ScriptedModel.calls(ctx.model), &(&1.records_received <= 4))
  end

  test "empty and all-success inputs return empty counts", ctx do
    assert {:ok, empty} = run(ctx, "empty")
    assert empty.state.counts == %{}

    assert empty.state.usage == %{
             calls: 1,
             steps: 2,
             bytes_read: 0,
             records_read: 0,
             max_depth: 0,
             peak_read_records: 0
           }

    rows = Enum.map(ctx.rows, &%{&1 | status: :ok})
    store = store(%{"success" => rows})
    assert {:ok, success} = run(%{ctx | store: store}, "success")
    assert success.state.counts == %{}
    assert success.state.turns == 2
  end

  test "irregular trees and both traversal orders agree with an independent oracle", ctx do
    for size <- [1, 2, 3, 17, 65, 257], leaf <- [1, 4, 16] do
      rows = Fixtures.logs(size)
      store = store(%{"fixture" => rows})

      results =
        for order <- [:forward, :reverse] do
          model = model(chunk_size: leaf, order: order)

          assert {:ok, candidate, []} =
                   RLM.cmd(Server.agent(ctx.agent), RLM.analyze_signal!("fixture"),
                     context: %{model: {ScriptedModel, model}, store: {Corpus, store}}
                   )

          assert candidate.state.counts == oracle(rows)
          assert_tree(candidate.state, size)
          candidate.state
        end

      [forward, reverse] = results
      assert forward.counts == reverse.counts
      assert forward.source_ranges == reverse.source_ranges
      assert forward.usage == reverse.usage
    end

    assert agent_result(ctx.agent).state_version == 0
  end

  test "a selected range reads only its records from a larger corpus", ctx do
    rows = Fixtures.logs(4_096)
    store = store(%{"large" => rows})

    assert {:ok, result} =
             run(%{ctx | store: store}, "large", range: %{offset: 1_000, length: 17})

    assert result.state.counts == oracle(Enum.slice(rows, 1_000, 17))
    assert result.state.usage.records_read == 17

    assert Enum.all?(
             Corpus.reads(store),
             &(&1.range.offset >= 1_000 and &1.range.offset + &1.range.length <= 1_017)
           )
  end

  for {limit, maximum} <- [
        max_depth: 0,
        max_calls: 1,
        max_steps: 1,
        max_read_records: 1,
        max_bytes: 0
      ] do
    test "#{limit} stops work before the allowance is exceeded", ctx do
      limit = unquote(limit)
      maximum = unquote(maximum)
      before = Server.snapshot(ctx.agent)

      assert {:error, %Error.ExecutionFailureError{details: details}} =
               run(ctx, "logs-v1", limits: %{limit => maximum})

      assert details.code == :budget_exhausted
      assert details.limit == limit
      assert details.maximum == maximum
      assert details.requested > maximum
      assert Server.snapshot(ctx.agent) == before

      successful_reads = Enum.filter(Corpus.reads(ctx.store), &match?({:ok, _}, &1.outcome))
      assert successful_reads == []

      if limit in [:max_depth, :max_calls, :max_steps],
        do: assert(length(ScriptedModel.calls(ctx.model)) == 1)
    end
  end

  test "the byte budget is shared across siblings and retains completed read effects", ctx do
    first_bytes = ctx.rows |> Enum.take(4) |> bytes()

    assert {:error, %Error.ExecutionFailureError{details: details}} =
             run(ctx, "logs-v1", limits: %{max_bytes: first_bytes})

    assert details.limit == :max_bytes
    assert details.usage.bytes_read == first_bytes
    assert [first, second] = Corpus.reads(ctx.store)
    assert first.outcome == {:ok, first_bytes}
    assert {:error, {:byte_limit, _, 0}} = second.outcome
    assert agent_result(ctx.agent).state_version == 0
  end

  test "call and step budgets are shared across siblings", ctx do
    for {limit, maximum} <- [max_calls: 4, max_steps: 6] do
      model = model(chunk_size: 4)
      store = store(%{"logs-v1" => ctx.rows})

      assert {:error, %Error.ExecutionFailureError{details: details}} =
               run(%{ctx | store: store, model: model}, "logs-v1", limits: %{limit => maximum})

      assert details.limit == limit
      assert details.usage.records_read > 0
      assert details.usage.calls <= 4
      if limit == :max_steps, do: assert(length(ScriptedModel.calls(model)) == maximum)
    end
  end

  test "exact work limits succeed", ctx do
    assert {:ok, baseline} = run(ctx, "logs-v1")
    usage = baseline.state.usage

    limits = %{
      max_calls: usage.calls,
      max_depth: usage.max_depth,
      max_steps: usage.steps,
      max_bytes: usage.bytes_read,
      max_read_records: usage.peak_read_records
    }

    assert {:ok, repeated} = run(ctx, "logs-v1", limits: limits)
    assert repeated.state.usage == usage
    assert repeated.state.counts == baseline.state.counts
    assert agent_result(ctx.agent).state_version == 2
  end

  test "gaps, overlaps, repeated ranges, and non-reducing recursion fail before reads", ctx do
    partitions = [
      [],
      [%{offset: 0, length: 17}],
      [%{offset: 0, length: 8}, %{offset: 9, length: 8}],
      [%{offset: 0, length: 9}, %{offset: 8, length: 9}],
      [%{offset: 0, length: 8}, %{offset: 0, length: 9}],
      [%{offset: 0, length: 0}, %{offset: 0, length: 17}]
    ]

    for ranges <- partitions do
      model = model(overrides: %{{0, 17, :start} => {:ok, %{op: :recurse, ranges: ranges}}})

      assert {:error, %Error.ExecutionFailureError{details: %{code: :invalid_partition}}} =
               run(%{ctx | model: model}, "logs-v1")
    end

    assert Corpus.reads(ctx.store) == []
    assert agent_result(ctx.agent).state_version == 0
  end

  test "malformed model replies and invalid transitions are rejected", ctx do
    for {reply, code} <- [
          {:bad_response, :invalid_adapter_response},
          {{:ok, %{op: :unknown}}, :invalid_decision},
          {{:ok, %{op: :recurse, ranges: [%{offset: -1, length: 1}]}}, :invalid_decision},
          {{:ok, %{op: :answer, counts: %{}}}, :invalid_transition}
        ] do
      model = model(overrides: %{{0, 17, :start} => reply})

      assert {:error, %Error.ExecutionFailureError{details: details}} =
               run(%{ctx | model: model}, "logs-v1")

      assert details.code == code
    end

    assert Corpus.reads(ctx.store) == []
  end

  test "false leaf counts and false parent counts cannot commit", ctx do
    for key <- [{0, 4, :read}, {0, 17, :children}] do
      model =
        model(
          chunk_size: 4,
          overrides: %{key => {:ok, %{op: :answer, counts: %{"invented" => 100}}}}
        )

      assert {:error, %Error.ExecutionFailureError{details: %{code: :unsupported_answer}}} =
               run(%{ctx | model: model}, "logs-v1")

      assert agent_result(ctx.agent).state_version == 0
    end

    assert Corpus.reads(ctx.store) != []
  end

  test "a late model failure preserves the last committed answer and permits retry", ctx do
    assert {:ok, _result} = run(ctx, "logs-v1")
    before = Server.snapshot(ctx.agent)
    reads_before = length(Corpus.reads(ctx.store))
    model = model(chunk_size: 4, overrides: %{{8, 9, :start} => {:error, :provider_timeout}})

    assert {:error,
            %Error.ExecutionFailureError{
              details: %{code: :adapter_error, reason: :provider_timeout}
            }} = run(%{ctx | model: model}, "logs-v1")

    assert Server.snapshot(ctx.agent) == before
    assert length(Corpus.reads(ctx.store)) == reads_before + 2
    assert {:ok, retried} = run(ctx, "logs-v1")
    assert retried.state.turns == 2
    assert agent_result(ctx.agent).state_version == 2
  end

  test "unknown corpora and ranges outside the corpus fail before model calls", ctx do
    assert {:error, %Error.ExecutionFailureError{details: %{reason: :unknown_corpus}}} =
             run(ctx, "missing")

    assert {:error, %Error.ExecutionFailureError{details: %{code: :range_outside_corpus}}} =
             run(ctx, "logs-v1", range: %{offset: 16, length: 2})

    assert ScriptedModel.calls(ctx.model) == []
    assert Corpus.reads(ctx.store) == []
  end

  test "invalid request schemas and missing clients fail before external work", ctx do
    for opts <- [
          [limits: %{max_calls: 0}],
          [limits: %{max_depth: 65}],
          [limits: %{max_bytes: -1}],
          [limits: %{max_steps: "ten"}],
          [range: %{offset: -1, length: 1}]
        ] do
      assert {:error, %Error.InvalidInputError{}} = run(ctx, "logs-v1", opts)
    end

    assert {:error, %Error.ExecutionFailureError{details: %{code: :invalid_clients}}} =
             Server.call(ctx.agent, RLM.analyze_signal!("logs-v1"))

    assert ScriptedModel.calls(ctx.model) == []
    assert Corpus.reads(ctx.store) == []
  end

  test "malformed store data and false byte totals fail without a commit", ctx do
    row = hd(ctx.rows)

    for payload <- [
          %{records: [], bytes: 0},
          %{records: [row], bytes: 0},
          %{
            records: [Map.put(row, :status, :unknown)],
            bytes: bytes([Map.put(row, :status, :unknown)])
          },
          :invalid
        ] do
      assert {:error, %Error.ExecutionFailureError{}} =
               RLM.analyze(
                 ctx.agent,
                 "broken",
                 {ScriptedModel, ctx.model},
                 {BrokenStore, {:ok, payload}}
               )

      assert agent_result(ctx.agent).state_version == 0
    end

    assert {:error, %Error.ExecutionFailureError{details: %{code: :adapter_error}}} =
             RLM.analyze(
               ctx.agent,
               "broken",
               {ScriptedModel, ctx.model},
               {BrokenStore, {:error, {:byte_limit, 0, 0}}}
             )
  end

  test "a skewed tree reaches the exact depth limit and rejects the next level", ctx do
    for size <- [65, 66] do
      rows = Fixtures.logs(size)
      store = store(%{"deep" => rows})

      overrides =
        Map.new(0..(size - 2), fn offset ->
          ranges = [
            %{offset: offset, length: 1},
            %{offset: offset + 1, length: size - offset - 1}
          ]

          {{offset, size - offset, :start}, {:ok, %{op: :recurse, ranges: ranges}}}
        end)

      model = model(chunk_size: 1, overrides: overrides)
      result = run(%{ctx | model: model, store: store}, "deep", limits: %{max_depth: 64})

      if size == 65 do
        assert {:ok, committed} = result
        assert committed.state.usage.max_depth == 64
        assert committed.state.counts == oracle(rows)
        assert_tree(committed.state, size)
      else
        assert {:error,
                %Error.ExecutionFailureError{details: %{limit: :max_depth, requested: 65}}} =
                 result

        assert agent_result(ctx.agent).state_version == 1
      end
    end
  end

  test "the final result can contain more services than any leaf result", ctx do
    rows = Fixtures.logs(4_096, services: 4_096)
    store = store(%{"many-services" => rows})
    assert {:ok, committed} = run(%{ctx | store: store}, "many-services")
    assert committed.state.counts == oracle(rows)
    assert map_size(committed.state.counts) == 820
    assert committed.state.usage.peak_read_records == 4
  end

  test "adapter exceptions and stopped stores return structured errors", ctx do
    assert {:error, %Error.ExecutionFailureError{details: %{reason: RuntimeError}}} =
             RLM.analyze(ctx.agent, "logs-v1", {RaisingModel, nil}, {Corpus, ctx.store})

    GenServer.stop(ctx.store)

    assert {:error,
            %Error.ExecutionFailureError{details: %{code: :adapter_error, operation: :describe}}} =
             run(ctx, "logs-v1")

    assert agent_result(ctx.agent).state_version == 0
  end

  test "cancellation stops recursive work after a read and preserves committed state", ctx do
    owner = self()
    before = Server.snapshot(ctx.agent)

    request =
      Task.async(fn ->
        RLM.analyze(ctx.agent, "logs-v1", {BarrierModel, {owner, ctx.model}}, {Corpus, ctx.store})
      end)

    assert_receive {:rlm_waiting, execution, %{depth: 2}}, 1_000
    monitor = Process.monitor(execution)
    assert Server.snapshot(ctx.agent) == before
    assert :ok = Server.cancel(ctx.agent)
    assert {:error, :cancelled} = Task.await(request)
    assert_receive {:DOWN, ^monitor, :process, ^execution, _}, 1_000
    assert Server.snapshot(ctx.agent) == before
    assert length(Corpus.reads(ctx.store)) == 1
    assert {:ok, _} = run(ctx, "logs-v1")
    assert agent_result(ctx.agent).state_version == 1
  end

  test "an execution deadline terminates a blocked model", ctx do
    owner = self()
    agent = agent(ctx.jido, exec_opts: [timeout: 500])

    request =
      Task.async(fn ->
        RLM.analyze(agent, "logs-v1", {BarrierModel, {owner, ctx.model}}, {Corpus, ctx.store})
      end)

    assert_receive {:rlm_waiting, execution, _}, 1_000
    monitor = Process.monitor(execution)
    assert {:error, %Error.TimeoutError{}} = Task.await(request, 2_000)
    assert_receive {:DOWN, ^monitor, :process, ^execution, _}, 1_000
    assert agent_result(agent).state_version == 0
    assert length(Corpus.reads(ctx.store)) == 1
  end

  test "queued requests retain their own client context and commit in order", ctx do
    owner = self()

    first =
      Task.async(fn ->
        RLM.analyze(ctx.agent, "logs-v1", {BarrierModel, {owner, ctx.model}}, {Corpus, ctx.store})
      end)

    assert_receive {:rlm_waiting, execution, _}, 1_000
    second = Task.async(fn -> run(ctx, "empty") end)
    eventually(fn -> Server.status(ctx.agent).admission.postponed == 1 end)
    assert agent_result(ctx.agent).state_version == 0
    send(execution, :release_rlm)
    assert {:ok, completed_first} = Task.await(first)
    assert completed_first.state.counts == oracle(ctx.rows)
    assert {:ok, completed_second} = Task.await(second)
    assert completed_second.state.counts == %{}
    assert completed_second.state.turns == 2
    assert agent_result(ctx.agent).state_version == 2
  end

  @tag timeout: 60_000
  test "a large tree stays within leaf bounds across concurrent Agents", ctx do
    rows = Fixtures.logs(16_384)
    store = store(%{"stress" => rows})
    agents = for _ <- 1..4, do: agent(ctx.jido)

    results =
      Task.async_stream(
        agents,
        fn agent ->
          RLM.analyze(agent, "stress", {ScriptedModel, ctx.model}, {Corpus, store},
            limits: %{max_calls: 8191, max_steps: 16382},
            timeout: 30000
          )
        end,
        max_concurrency: 4,
        timeout: 35_000
      )
      |> Enum.to_list()

    for {:ok, result} <- results do
      assert {:ok, committed} = result
      assert committed.state.counts == oracle(rows)
      assert committed.state.usage.calls == 8_191
      assert committed.state.usage.steps == 16_382
      assert committed.state.usage.peak_read_records == 4
      assert committed.state.usage.bytes_read == bytes(rows)
      assert_tree(committed.state, 16_384)
    end

    assert length(results) == 4
    assert Enum.all?(results, &match?({:ok, {:ok, _}}, &1))
    assert Enum.all?(agents, &(agent_result(&1).state_version == 1))
    assert length(Corpus.reads(store)) == 4 * 4_096
  end

  defp store(corpora),
    do: start_supervised!(%{id: make_ref(), start: {Corpus, :start_link, [corpora]}})

  defp model(opts),
    do: start_supervised!(%{id: make_ref(), start: {ScriptedModel, :start_link, [opts]}})

  defp agent(jido, opts \\ []),
    do: start_agent!(jido, RLM, Keyword.put(opts, :error_policy, fn _, _ -> :continue end))

  defp clients(ctx), do: %{model: {ScriptedModel, ctx.model}, store: {Corpus, ctx.store}}

  defp run(ctx, corpus, opts \\ []),
    do: RLM.analyze(ctx.agent, corpus, {ScriptedModel, ctx.model}, {Corpus, ctx.store}, opts)

  defp bytes(rows), do: Enum.reduce(rows, 0, &(&2 + byte_size(:erlang.term_to_binary(&1))))

  defp oracle(rows),
    do: rows |> Enum.filter(&(&1.status == :failed)) |> Enum.frequencies_by(& &1.service)

  defp assert_tree(state, count) do
    assert length(state.call_tree) == state.usage.calls
    assert Enum.map(state.call_tree, & &1.id) == Enum.to_list(1..state.usage.calls)
    by_id = Map.new(state.call_tree, &{&1.id, &1})
    assert %{parent_id: 0, depth: 0, range: %{offset: 0, length: ^count}} = by_id[1]

    for node <- tl(state.call_tree) do
      parent = Map.fetch!(by_id, node.parent_id)
      assert node.depth == parent.depth + 1
      assert node.range.length < parent.range.length
      assert node.range.offset >= parent.range.offset
      assert node.range.offset + node.range.length <= parent.range.offset + parent.range.length
    end

    {end_offset, read_count} =
      Enum.reduce(state.source_ranges, {0, 0}, fn range, {offset, total} ->
        assert range.offset == offset
        {offset + range.length, total + range.length}
      end)

    assert end_offset == count
    assert read_count == count
  end
end

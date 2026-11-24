defmodule Jido.AgentServer.DurableTurn.CheckpointStoreTest do
  use Jido.Test.Case, async: true
  use Covenant.Case, component: "jido.agent_server.durable_turn", async: true

  alias Jido.Durable.Runtime
  alias Jido.Persistence.ContinuationStore, as: Store
  alias Jido.Persistence.ContinuationStore.{JoinCompletedRef, SharedToolPayload, ToolPayload}
  alias Jido.Test.AgentServer.DurableFixtures, as: F

  defmodule Increment do
    use Jido.Action, name: "checkpoint_hydration_increment"

    @impl true
    def run(%{value: value}, _context), do: {:ok, %{value: value + 1}}
  end

  defmodule HydrationFlow do
    use Jido.Flow, name: "checkpoint_hydration_flow"

    flow do
      step "one", action: Increment, params: %{value: input(:value)}
      step "two", action: Increment, params: %{value: result("one", :value)}
      output result("two")
    end
  end

  defmodule Bytes do
    @behaviour Jido.Persistence.Store

    def validate_options(opts) do
      allowed = [:delete_owner, :store]

      if Keyword.keyword?(opts) and Keyword.keys(opts) -- allowed == [] and
           Keyword.keys(opts) == Enum.uniq(Keyword.keys(opts)) and is_pid(opts[:store]),
         do: :ok,
         else: {:error, :invalid_options}
    end

    def get(key, opts) do
      Agent.get(opts[:store], fn records ->
        case Map.fetch(records, key) do
          {:ok, bytes} -> {:ok, bytes, token(bytes)}
          :error -> {:error, :not_found}
        end
      end)
    end

    def compare_and_swap(key, expected, bytes, opts) do
      Agent.get_and_update(opts[:store], fn records ->
        stored = Map.get(records, key, :not_found)

        matches? =
          case expected do
            {:token, expected} when is_binary(stored) -> token(stored) == expected
            _ -> stored == expected
          end

        if matches?,
          do: {:ok, Map.put(records, key, bytes)},
          else: {{:error, :conflict}, records}
      end)
    end

    defp token(bytes), do: :crypto.hash(:sha256, bytes)

    def delete(key, opts) do
      if owner = opts[:delete_owner] do
        first? = is_nil(Process.get(:checkpoint_delete_started))
        Process.put(:checkpoint_delete_started, true)

        if first? do
          send(owner, {:checkpoint_delete_started, self(), key})

          receive do
            {:continue_checkpoint_delete, ^key} -> :ok
          end
        end
      end

      Agent.update(opts[:store], &Map.delete(&1, key))
    end
  end

  defmodule BarrierBytes do
    @behaviour Jido.Persistence.Store
    alias Jido.AgentServer.DurableTurn.CheckpointStoreTest.Bytes

    def validate_options(opts) do
      allowed = [:barrier_owner, :barrier_stage, :delete_owner, :store]

      if Keyword.keyword?(opts) and Keyword.keys(opts) -- allowed == [] and
           Keyword.keys(opts) == Enum.uniq(Keyword.keys(opts)) and is_pid(opts[:store]),
         do: :ok,
         else: {:error, :invalid_options}
    end

    def get(key, opts), do: Bytes.get(key, opts)
    def delete(key, opts), do: Bytes.delete(key, opts)

    def compare_and_swap(key, expected, bytes, opts) do
      stage = Keyword.fetch!(opts, :barrier_stage)

      if barrier_key?(stage, key) and is_nil(Process.get({__MODULE__, stage})) do
        Process.put({__MODULE__, stage}, true)
        owner = Keyword.fetch!(opts, :barrier_owner)
        send(owner, {:fact_cas_ready, stage, self(), key})

        receive do
          {:continue_fact_cas, ^stage, ^key} -> :ok
        end
      end

      Bytes.compare_and_swap(key, expected, bytes, opts)
    end

    defp barrier_key?(:index, key), do: String.ends_with?(key, ":facts:index")

    defp barrier_key?(:fact, key) do
      String.contains?(key, ":facts:") and
        not String.ends_with?(key, ":facts:index")
    end
  end

  setup c do
    store = start_supervised!({Agent, fn -> %{} end})
    config = {Bytes, store: store}
    init = %{jido: c.jido, partition: "north", agent_id: "worker"}
    id = identity(init, "job")
    assert :ok = Store.register(c.jido, id, config)
    %{store: store, config: config, init: init, id: id}
  end

  @tag obligation: "jido.agent_server.durable_turn.I2"
  test "Runic appends each event batch once and streams committed events in order", c do
    assert Code.ensure_loaded?(Store)
    assert Runic.Runner.Store.supports_stream?(Store)
    assert {:error, :not_found} = Store.stream(c.id, c.jido)

    first = [%{event: 1}, %{event: 2}]
    second = [%{event: 3}]
    assert {:ok, 1} = Store.append(c.id, first, c.jido)
    assert {:ok, 2} = Store.append(c.id, second, c.jido)
    assert {:ok, events} = Store.stream(c.id, c.jido)
    assert Enum.to_list(events) == first ++ second

    records = Agent.get(c.store, &Map.values/1)
    assert length(records) == 3

    decoded = Enum.map(records, fn bytes -> elem(Jido.Persistence.Codec.Term.decode(bytes, trusted: true), 1) end)
    assert Enum.count(decoded, &(&1 == 2)) == 1
    assert Enum.count(decoded, &is_list/1) == 2

    assert Enum.sort(Enum.filter(decoded, &is_list/1)) ==
             Enum.sort([first, second])
  end

  @tag obligation: "jido.agent_server.durable_turn.I2"
  test "stores one copy of a completion fact and restores the full event", c do
    alias Runic.Workflow.{Fact, RunnableCompleted}
    alias Runic.Workflow.Events.FactProduced

    value = :binary.copy("completion value ", 1_024)
    fact = Fact.new(value: value)
    produced = %{FactProduced.new(fact, producer_label: :produced, weight: 0) | value: nil}
    completed = %RunnableCompleted{runnable_id: "action", result_fact: fact}

    assert :ok = Store.save_fact(c.id, fact.hash, value, c.jido)
    assert {:ok, 1} = Store.append(c.id, [produced, completed], c.jido)
    assert {:ok, 2} = Store.append(c.id, [completed], c.jido)
    assert {:ok, [^produced, ^completed, ^completed]} = Store.stream(c.id, c.jido)

    records = Agent.get(c.store, & &1)
    {_, compact} = Enum.find(records, fn {key, _} -> String.ends_with?(key, ":batches:1") end)
    {_, inline} = Enum.find(records, fn {key, _} -> String.ends_with?(key, ":batches:2") end)
    assert byte_size(compact) < byte_size(value)
    assert {:ok, [^completed]} = Jido.Persistence.Codec.Term.decode(inline, trusted: true)

    {fact_key, _} =
      Enum.find(records, fn {key, _} ->
        String.contains?(key, ":facts:") and not String.ends_with?(key, ":facts:index")
      end)

    Agent.update(c.store, &Map.delete(&1, fact_key))
    assert {:error, :invalid_execution_checkpoint} = Store.stream(c.id, c.jido)
  end

  @tag obligation: "jido.agent_server.durable_turn.I2"
  test "dispatch references require a saved fact with the exact value and restore after replacement", c do
    alias Runic.Workflow.{Fact, FactRef, RunnableDispatched}

    value = :binary.copy("dispatch input / ", 512)
    fact = Fact.new(value: value)
    dispatch = %RunnableDispatched{runnable_id: "saved", input_fact: fact}
    different = %RunnableDispatched{runnable_id: "different", input_fact: %{fact | value: :different}}
    missing = %RunnableDispatched{runnable_id: "missing", input_fact: Fact.new(value: :missing)}
    assert :ok = Store.save_fact(c.id, fact.hash, value, c.jido)

    replacement = start_supervised!({Agent, fn -> nil end}, id: :replacement)
    assert :ok = Store.register(c.jido, c.id, c.config, replacement)
    assert {:ok, 1} = Store.append(c.id, [dispatch, different, missing], c.jido)
    assert {:ok, [^dispatch, ^different, ^missing]} = Store.stream(c.id, c.jido)

    records = Agent.get(c.store, & &1)
    {_, batch} = Enum.find(records, fn {key, _} -> String.ends_with?(key, ":batches:1") end)
    hash = fact.hash

    assert {:ok, [%RunnableDispatched{input_fact: %FactRef{hash: ^hash}}, ^different, ^missing]} =
             Jido.Persistence.Codec.Term.decode(batch, trusted: true)

    assert :binary.match(batch, value) == :nomatch

    fact_key =
      Enum.find(Map.keys(records), fn key ->
        String.contains?(key, ":facts:") and not String.ends_with?(key, ":index")
      end)

    Agent.update(c.store, &Map.delete(&1, fact_key))
    assert {:error, :invalid_execution_checkpoint} = Store.stream(c.id, c.jido)
  end

  @tag obligation: "jido.agent_server.durable_turn.I2"
  test "the fact index compacts occurrence keys and preserves legacy and opaque keys after restart", c do
    alias Jido.Persistence.{Config, Inspector}
    alias Jido.Persistence.Codec.Term
    alias Runic.Workflow.Fact

    first = Fact.new(value: :first)
    second = Fact.new(value: :second)
    opaque = first.hash.digest

    assert :ok = Store.save_fact(c.id, first.hash, first.value, c.jido)
    assert :ok = Store.save_fact(c.id, opaque, :opaque, c.jido)
    index = Agent.get(c.store, fn records -> Enum.find(Map.keys(records), &String.ends_with?(&1, ":facts:index")) end)
    assert {:ok, legacy} = Term.encode({:jido_fact_index, 1, [opaque, first.hash]})
    Agent.update(c.store, &Map.put(&1, index, legacy))

    replacement = start_supervised!({Agent, fn -> nil end}, id: :index_replacement)
    assert :ok = Store.register(c.jido, c.id, c.config, replacement)
    assert :ok = Store.save_fact(c.id, second.hash, second.value, c.jido)
    assert :ok = Store.save_fact(c.id, second.hash, second.value, c.jido)
    bytes = Agent.get(c.store, &Map.fetch!(&1, index))
    hashes = [second.hash, opaque, first.hash]

    assert {:ok, {:jido_fact_index, 2, _entries}} = Term.decode(bytes, trusted: true)
    assert {:ok, expanded} = Term.encode({:jido_fact_index, 1, hashes})
    assert byte_size(bytes) * 2 < byte_size(expanded)
    assert {:ok, profile} = Config.open(c.config)
    assert {:ok, {:jido_fact_index, 1, ^hashes}} = Inspector.read(profile, index, full: true)
    assert :ok = Store.register(c.jido, c.id, c.config)
    assert {:ok, :first} = Store.load_fact(c.id, first.hash, c.jido)
    assert {:ok, :second} = Store.load_fact(c.id, second.hash, c.jido)
    assert {:ok, :opaque} = Store.load_fact(c.id, opaque, c.jido)
  end

  @tag obligation: "jido.agent_server.durable_turn.I2"
  test "execution references require a saved preparation and reject a missing source", c do
    input = :binary.copy("durable AI input / ", 64)
    signal = Jido.Signal.new!("jido.ai.request", %{input: input}, source: "/test")
    preparation = %{signal: signal}
    value = %{input: input, repeated: input}

    assert :ok = Store.prepare(c.jido, c.id, preparation)
    assert :ok = Store.prepare(c.jido, c.id, preparation)
    assert {:error, :execution_prepare_conflict} = Store.prepare(c.jido, c.id, %{signal: %{signal | data: %{}}})

    replacement = start_supervised!({Agent, fn -> nil end}, id: :prepared_replacement)
    assert :ok = Store.register(c.jido, c.id, c.config, replacement)
    assert :ok = Store.save_fact(c.id, :input, value, c.jido)
    assert {:ok, 1} = Store.append(c.id, [value], c.jido)

    records = Agent.get(c.store, & &1)
    {prepared_key, prepared} = Enum.find(records, fn {key, _} -> String.ends_with?(key, ":prepared") end)
    {batch_key, batch} = Enum.find(records, fn {key, _} -> String.ends_with?(key, ":batches:1") end)
    assert :binary.match(prepared, input) != :nomatch

    assert {:ok, {:jido_tool_payload_refs, 1, segments}} =
             Jido.Persistence.Codec.Term.decode(batch, trusted: true)

    digest = :crypto.hash(:sha256, input)
    assert {:prepared, digest} in segments
    assert :binary.match(batch, input) == :nomatch
    assert {:ok, ^value} = Store.load_fact(c.id, :input, c.jido)
    assert {:ok, [^value]} = Store.stream(c.id, c.jido)
    assert {:ok, profile} = Jido.Persistence.Config.open(c.config)
    assert {:ok, [^value]} = Store.inspect_record(profile, batch_key, {:jido_tool_payload_refs, 1, segments})

    circular = {:jido_tool_payload_refs, 1, [{:prepared, digest}]}
    assert {:ok, circular_bytes} = Jido.Persistence.Codec.Term.encode(circular)
    Agent.update(c.store, &Map.put(&1, prepared_key, circular_bytes))
    assert {:error, :invalid_execution_checkpoint} = Store.load_fact(c.id, :input, c.jido)
    assert {:error, :invalid_execution_checkpoint} = Jido.Persistence.Inspector.read(profile, prepared_key, full: true)

    Agent.update(c.store, &Map.delete(&1, prepared_key))
    assert {:error, :invalid_execution_checkpoint} = Store.load_fact(c.id, :input, c.jido)
    assert {:error, :invalid_execution_checkpoint} = Store.stream(c.id, c.jido)
  end

  @tag obligation: "jido.agent_server.durable_turn.I2"
  test "writes plain execution records by default and reads both encodings after opt-in", c do
    alias Jido.Persistence.Codec.Term

    payload = Enum.map_join(1..128, &:crypto.hash(:sha256, <<&1::32>>))
    value = %{input: payload, copies: List.duplicate(payload, 4)}

    assert :ok = Store.prepare(c.jido, c.id, value)
    assert :ok = Store.save_fact(c.id, :plain, value, c.jido)
    assert {:ok, 1} = Store.append(c.id, [value], c.jido)

    plain_records = Agent.get(c.store, & &1)
    plain_payloads = execution_payloads(plain_records)
    assert length(plain_payloads) == 3

    for bytes <- plain_payloads do
      assert {:ok, term} = Term.decode(bytes, trusted: true)
      assert {:ok, ^bytes} = Term.encode(term)
    end

    assert :ok = Store.register(c.jido, c.id, store: c.config, execution_compression: true)
    assert :ok = Store.prepare(c.jido, c.id, value)
    assert :ok = Store.save_fact(c.id, :compact, value, c.jido)
    assert {:ok, 2} = Store.append(c.id, [value], c.jido)

    compact_id = identity(c.init, "compact-job")
    assert :ok = Store.register(c.jido, compact_id, store: c.config, execution_compression: true)
    assert :ok = Store.prepare(c.jido, compact_id, value)

    new_payloads = Agent.get(c.store, &Map.drop(&1, Map.keys(plain_records))) |> execution_payloads()
    assert length(new_payloads) == 3
    assert {:ok, plain} = Term.encode(value)

    for bytes <- new_payloads do
      assert byte_size(bytes) < div(byte_size(plain), 2)
    end

    assert :ok = Store.register(c.jido, c.id, c.config)
    assert {:ok, [^value, ^value]} = Store.stream(c.id, c.jido)
    assert {:ok, ^value} = Store.load_fact(c.id, :plain, c.jido)
    assert {:ok, ^value} = Store.load_fact(c.id, :compact, c.jido)
  end

  @tag obligation: "jido.agent_server.durable_turn.I2"
  test "repairs a tail chunk before the next append", c do
    assert {:ok, 1} = Store.append(c.id, [:first], c.jido)

    count_key =
      Agent.get(c.store, fn records ->
        records |> Map.keys() |> Enum.find(&(not String.contains?(&1, ":batches:")))
      end)

    Agent.update(c.store, &Map.delete(&1, count_key))

    assert {:ok, 2} = Store.append(c.id, [:second], c.jido)
    assert {:ok, [:first, :second]} = Store.stream(c.id, c.jido)
  end

  @tag obligation: "jido.agent_server.durable_turn.I2"
  test "read and repair return an error for an invalid saved batch", c do
    assert {:ok, 1} = Store.append(c.id, [:first], c.jido)
    {:ok, config} = Jido.Persistence.Config.open(c.config)
    {:ok, invalid_batch} = Jido.Persistence.Config.encode(config, 1)
    records = Agent.get(c.store, & &1)
    batch_key = Enum.find(Map.keys(records), &String.ends_with?(&1, ":batches:1"))
    count_key = Enum.find(Map.keys(records), &(&1 != batch_key))
    committed = Map.put(records, batch_key, invalid_batch)
    tail = Map.delete(committed, count_key)

    for invalid <- [committed, tail] do
      Agent.update(c.store, fn _records -> invalid end)
      assert {:error, :invalid_execution_checkpoint} = Store.read_workflow(config, c.id)
      assert {:error, :invalid_execution_checkpoint} = Store.stream(c.id, c.jido)
      assert Agent.get(c.store, & &1) == invalid
    end
  end

  @tag obligation: "jido.agent_server.durable_turn.I2"
  test "Session, attempts, and reply reuse tool payloads across execution records", c do
    payload = String.duplicate("one stored tool value 12345 ", 300)
    slot = "run/0:0"
    call = %{name: "read"}
    result = {%{normalized: %{status: :ok, model_content: payload}}, []}
    record_tool = Store.tool_recorder(c.jido, c.id)

    assert {:ok, ^result} = record_tool.(slot, call, fn -> result end)
    assert {:ok, ^result} = record_tool.(slot, call, fn -> flunk("completed tool ran again") end)

    assert {:error, :tool_call_changed_on_replay} =
             record_tool.(slot, %{name: "write"}, fn -> flunk("a different tool ran on replay") end)

    values = %{
      session: %{entries: [%{payload: payload}]},
      tool_attempts: [%{output: payload}],
      reply: %{output: payload}
    }

    assert :ok = Store.save_fact(c.id, :values, values, c.jido)
    assert {:ok, 1} = Store.append(c.id, [values], c.jido)

    replacement = start_supervised!({Agent, fn -> nil end}, id: :replacement)
    assert :ok = Store.register(c.jido, c.id, c.config, replacement)
    assert {:ok, 2} = Store.append(c.id, [values], c.jido)
    assert {:ok, ^values} = Store.load_fact(c.id, :values, c.jido)
    assert {:ok, [^values, ^values]} = Store.stream(c.id, c.jido)

    records = Agent.get(c.store, & &1)
    assert [{source, receipt}] = Enum.filter(records, fn {_, bytes} -> :binary.match(bytes, payload) != :nomatch end)
    assert String.contains?(source, ":facts:")
    assert {:ok, {:jido_tool_result, 1, _, _, _}} = Jido.Persistence.Codec.Term.decode(receipt, [])
    assert length(:binary.matches(receipt, payload)) == 1
    refute Enum.any?(Map.keys(records), &String.starts_with?(&1, "jido:tool-payload:"))

    Agent.update(c.store, &Map.put(&1, source, "wrong content"))
    assert {:error, :invalid_execution_checkpoint} = Store.stream(c.id, c.jido)
    assert {:error, :invalid_execution_checkpoint} = Store.load_fact(c.id, :values, c.jido)

    Agent.update(c.store, &Map.delete(&1, source))
    assert {:error, :invalid_execution_checkpoint} = Store.stream(c.id, c.jido)
    assert {:error, :invalid_execution_checkpoint} = Store.load_fact(c.id, :values, c.jido)
  end

  @tag obligation: "jido.agent_server.durable_turn.I2"
  test "inspects a preparation that owns a prior tool result", c do
    alias Jido.Persistence.Inspector

    payload = String.duplicate("stored tool output / ", 256)

    session =
      Jido.Session.append(Jido.Session.new(), %{kind: :ai_message, payload: %{"role" => "tool", "output" => payload}})

    later_id = identity(c.init, "later")
    assert :ok = Store.register(c.jido, later_id, c.config)
    signal = Jido.Signal.new!("jido.ai.request", %{input: "Continue."}, source: "/test")
    prepared = %{signal: signal, context: %{jido_ai_session: Jido.Session.encode(session)}}
    assert :ok = Store.prepare(c.jido, later_id, prepared)
    assert :ok = Store.save_fact(later_id, :output, payload, c.jido)
    records = Agent.get(c.store, & &1)
    assert [{prepared_key, _}] = Enum.filter(records, fn {_, bytes} -> :binary.match(bytes, payload) != :nomatch end)
    assert String.ends_with?(prepared_key, ":prepared")
    {:ok, profile} = Jido.Persistence.Config.open(c.config)

    assert {:ok, %{kind: "execution_prepared"}} = Inspector.read(profile, prepared_key)
    assert {:ok, {:jido_execution_prepared, 3, ^prepared}} = Inspector.read(profile, prepared_key, full: true)
    assert {:ok, ^payload} = Store.load_fact(later_id, :output, c.jido)
  end

  @tag obligation: "jido.agent_server.durable_turn.I2"
  test "restores a prior receipt that references a shared payload", c do
    payload = String.duplicate("legacy tool value 12345 ", 300)
    slot = "run/0:0"
    call = %{name: "read"}
    result = {%{normalized: %{status: :ok, model_content: payload}}, []}
    record_tool = Store.tool_recorder(c.jido, c.id)
    assert {:ok, ^result} = record_tool.(slot, call, fn -> result end)
    {:ok, profile} = Jido.Persistence.Config.open(c.config)
    records = Agent.get(c.store, & &1)

    [{receipt_key, signature}] =
      for {key, bytes} <- records,
          {:ok, {:jido_tool_result, 1, signature, _, _}} <- [Jido.Persistence.Config.decode(profile, bytes)],
          do: {key, signature}

    digest = ToolPayload.digest(payload)
    shared = ToolPayload.add_shared(ToolPayload.new(), %{digest => payload})
    assert {:ok, encoded} = Jido.Persistence.Config.encode(profile, result)
    receipt = {:jido_tool_result, 2, signature, [digest], ToolPayload.pack(encoded, shared)}
    assert {:ok, encoded_receipt} = Jido.Persistence.Config.encode(profile, receipt)

    {:jido_execution, namespace, partition, agent_id, _turn_id} = c.id
    scope = Base.url_encode64(:erlang.term_to_binary({namespace, partition, agent_id}), padding: false)
    payload_key = "jido:tool-payload:v1:" <> scope <> ":" <> Base.url_encode64(digest, padding: false)
    Agent.update(c.store, &(&1 |> Map.put(receipt_key, encoded_receipt) |> Map.put(payload_key, payload)))

    assert {:ok, %{kind: "tool_payload", bytes: size}} = Jido.Persistence.Inspector.read(profile, payload_key)
    assert size == byte_size(payload)
    other_partition = identity(%{c.init | partition: "south"}, "job")
    assert {:error, :not_found} = SharedToolPayload.read(profile, other_partition, digest)

    replacement = start_supervised!({Agent, fn -> nil end}, id: :replacement)
    assert :ok = Store.register(c.jido, c.id, c.config, replacement)
    assert {:ok, ^result} = record_tool.(slot, call, fn -> flunk("completed tool ran again") end)
    assert :ok = Store.save_fact(c.id, :values, result, c.jido)
    assert {:ok, ^result} = Store.load_fact(c.id, :values, c.jido)
  end

  @tag obligation: "jido.agent_server.durable_turn.I2"
  test "stores and restores one complete fact value", c do
    value = %{input: %{session: large_session()}, results: %{}}

    assert :ok = Store.save_fact(c.id, :fact, value, c.jido)
    assert {:ok, ^value} = Store.load_fact(c.id, :fact, c.jido)
  end

  @tag obligation: "jido.agent_server.durable_turn.I2"
  test "rejects a conflicting value for one fact identity", c do
    assert :ok = Store.save_fact(c.id, :same, %{value: 1}, c.jido)
    assert :ok = Store.save_fact(c.id, :same, %{value: 1}, c.jido)

    assert {:error, :fact_value_conflict} =
             Store.save_fact(c.id, :same, %{value: 2}, c.jido)

    assert {:ok, %{value: 1}} = Store.load_fact(c.id, :same, c.jido)
  end

  @tag obligation: "jido.agent_server.durable_turn.I2"
  test "retries a concurrent fact index update", c do
    use_barrier_store(c, :index)

    left = Task.async(fn -> Store.save_fact(c.id, :left, %{value: 1}, c.jido) end)
    right = Task.async(fn -> Store.save_fact(c.id, :right, %{value: 2}, c.jido) end)

    release_fact_barrier(:index, 2)

    assert :ok = Task.await(left)
    assert :ok = Task.await(right)
    assert {:ok, %{value: 1}} = Store.load_fact(c.id, :left, c.jido)
    assert {:ok, %{value: 2}} = Store.load_fact(c.id, :right, c.jido)
  end

  @tag obligation: "jido.agent_server.durable_turn.I2"
  test "accepts concurrent idempotent writes for one fact", c do
    use_barrier_store(c, :fact)
    value = %{value: large_session()}

    left = Task.async(fn -> Store.save_fact(c.id, :same, value, c.jido) end)
    right = Task.async(fn -> Store.save_fact(c.id, :same, value, c.jido) end)

    release_fact_barrier(:fact, 2)

    assert :ok = Task.await(left)
    assert :ok = Task.await(right)
    assert {:ok, ^value} = Store.load_fact(c.id, :same, c.jido)
  end

  @tag obligation: "jido.agent_server.durable_turn.I2"
  test "rejects a fact value that does not match its stored digest", c do
    assert :ok = Store.save_fact(c.id, :checked, %{value: 1}, c.jido)

    {key, record} =
      Agent.get(c.store, fn records ->
        Enum.find_value(records, fn {key, bytes} ->
          case Jido.Persistence.Codec.Term.decode(bytes, trusted: true) do
            {:ok, {:jido_fact_value, 1, 0, digest, :full, %{value: 1}}} ->
              {key, {:jido_fact_value, 1, 0, digest, :full, %{value: 2}}}

            _other ->
              nil
          end
        end)
      end)

    {:ok, bytes} = Jido.Persistence.Codec.Term.encode(record)
    Agent.update(c.store, &Map.put(&1, key, bytes))

    assert {:error, :invalid_execution_checkpoint} = Store.load_fact(c.id, :checked, c.jido)
  end

  @tag obligation: "jido.agent_server.durable_turn.I2"
  test "stores a JoinCompleted result as a fact reference", c do
    value = [%{input: %{session: large_session()}, results: %{}}]

    event = %Runic.Workflow.Events.JoinCompleted{
      join_hash: :join,
      result_fact_hash: :joined,
      result_value: value,
      result_ancestry: {:join, :parent},
      contribution_fact_hashes: [:left, :right],
      weight: 2
    }

    assert {:ok, 1} = Store.append(c.id, [event], c.jido)

    stored_events =
      Agent.get(c.store, fn records ->
        records
        |> Map.values()
        |> Enum.map(fn bytes -> elem(Jido.Persistence.Codec.Term.decode(bytes, trusted: true), 1) end)
        |> Enum.find(&is_list/1)
      end)

    assert [%{event | result_value: nil}] == stored_events

    assert {:ok,
            [
              %JoinCompletedRef{
                join_hash: :join,
                result_fact_hash: :joined,
                result_ancestry: {:join, :parent},
                contribution_fact_hashes: [:left, :right],
                weight: 2
              }
            ]} = Store.stream(c.id, c.jido)

    assert {:ok, ^value} = Store.load_fact(c.id, :joined, c.jido)
  end

  @tag obligation: "jido.agent_server.durable_turn.I2"
  test "rebuilds nested Join lists from ordered saved facts after replacement", c do
    alias Jido.Persistence.{Config, Inspector}
    alias Jido.Persistence.Codec.Term
    alias Runic.Workflow.Events.JoinCompleted

    left = :binary.copy("first contribution / ", 256)
    right = :binary.copy("second contribution / ", 256)
    assert :ok = Store.save_fact(c.id, :left, left, c.jido)
    assert :ok = Store.save_fact(c.id, :right, right, c.jido)
    assert :ok = Store.save_fact(c.id, :empty, nil, c.jido)

    first = %JoinCompleted{
      join_hash: :join,
      result_fact_hash: :joined,
      result_value: [right, left, nil, right],
      result_ancestry: {:join, :parent},
      contribution_fact_hashes: [:right, :left, :empty, :right],
      weight: 2
    }

    second = %{
      first
      | result_fact_hash: :nested,
        result_value: [left, first.result_value],
        contribution_fact_hashes: [:left, :joined]
    }

    assert {:ok, 1} = Store.append(c.id, [first, second], c.jido)
    records = Agent.get(c.store, & &1)

    join_records =
      for {key, bytes} <- records,
          {:ok, {:jido_fact_value, 1, 0, digest, :join, hashes}} <- [Term.decode(bytes, trusted: true)],
          into: %{},
          do: {hashes, {key, bytes, digest}}

    assert %{
             [:right, :left, :empty, :right] => {_first_key, first_bytes, _digest},
             [:left, :joined] => {nested_key, nested_bytes, nested_digest}
           } = join_records

    assert byte_size(first_bytes) < byte_size(left)
    assert byte_size(nested_bytes) < byte_size(left)

    replacement = start_supervised!({Agent, fn -> nil end}, id: :join_replacement)
    assert :ok = Store.register(c.jido, c.id, c.config, replacement)
    expected = second.result_value
    assert {:ok, ^expected} = Store.load_fact(c.id, :nested, c.jido)
    assert {:ok, profile} = Config.open(c.config)

    assert {:ok, {:jido_fact_value, 1, 0, ^nested_digest, :full, ^expected}} =
             Inspector.read(profile, nested_key, full: true)

    assert {:ok, cyclic} = Term.encode({:jido_fact_value, 1, 0, nested_digest, :join, [:nested]})
    Agent.update(c.store, &Map.put(&1, nested_key, cyclic))
    assert {:error, :invalid_execution_checkpoint} = Store.load_fact(c.id, :nested, c.jido)

    {right_key, _bytes} =
      Enum.find(records, fn {_key, bytes} ->
        match?({:ok, {:jido_fact_value, 1, 0, _, :full, ^right}}, Term.decode(bytes, trusted: true))
      end)

    Agent.update(c.store, fn _ -> Map.delete(records, right_key) end)
    assert {:error, :invalid_execution_checkpoint} = Store.load_fact(c.id, :nested, c.jido)
  end

  @tag obligation: "jido.agent_server.durable_turn.I2"
  test "checkpoint keys use the stable unpadded encoding", c do
    id = {:jido_execution, "n", "p", "a", "t"}
    assert :ok = Store.register(c.jido, id, c.config)
    assert {:ok, 1} = Store.append(id, [:event], c.jido)

    expected =
      "jido:execution:v3:" <>
        Base.url_encode64(:erlang.term_to_binary(id), padding: false)

    assert expected in Agent.get(c.store, &Map.keys/1)
  end

  @tag obligation: "jido.agent_server.durable_turn.I2"
  test "rejects an invalid batch count", c do
    key =
      "jido:execution:v3:" <>
        Base.url_encode64(:erlang.term_to_binary(c.id), padding: false)

    Agent.update(c.store, &Map.put(&1, key, :erlang.term_to_binary(:invalid)))

    assert {:error, :invalid_execution_checkpoint} = Store.stream(c.id, c.jido)
    assert {:error, :invalid_execution_checkpoint} = Store.append(c.id, [:event], c.jido)
  end

  @tag obligation: "jido.agent_server.durable_turn.I9"
  @tag timeout: 1_000
  test "terminal cleanup unregisters immediately and deletes asynchronously", c do
    config = {Bytes, store: c.store, delete_owner: self()}
    assert :ok = Store.register(c.jido, c.id, config)
    assert {:ok, 1} = Store.append(c.id, [:graph], c.jido)
    assert {:ok, 2} = Store.append(c.id, [:more_graph], c.jido)
    assert :ok = Store.save_fact(c.id, :orphan, %{value: 1}, c.jido)

    Agent.update(c.store, fn records ->
      {batch_key, _bytes} =
        Enum.find(records, fn {key, _bytes} -> String.contains?(key, ":batches:") end)

      Map.put(records, batch_key, :erlang.term_to_binary(:damaged))
    end)

    assert :ok = Store.collect(c.jido, c.id)
    assert_receive {:checkpoint_delete_started, delete_task, key}
    assert {:error, :execution_store_unavailable} = Store.stream(c.id, c.jido)
    assert Agent.get(c.store, &map_size/1) > 3

    send(delete_task, {:continue_checkpoint_delete, key})
    eventually(fn -> Agent.get(c.store, & &1) == %{} end)
  end

  @tag obligation: ["jido.agent_server.durable_turn.I2", "jido.agent_server.durable_turn.I11"]
  test "ordinary IDs have no execution store", c do
    assert {:error, :not_found} = Store.stream("ordinary-action", c.jido)
  end

  @tag obligation: "jido.agent_server.durable_turn.I2"
  test "an unchanged workflow transition preserves the saved graph", c do
    {:ok, workflow} = Jido.Exec.compile(F.Flow, [])
    workflow = Runic.Workflow.enable_event_emission(workflow)
    log = Runic.Workflow.event_log(workflow)

    assert {:ok, _batch_count} = Store.append(c.id, log, c.jido)

    assert {:ok, restored} =
             Store.update_workflow(c.jido, c.id, fn current -> {:ok, current} end)

    assert Runic.Workflow.event_log(restored) == log
    assert {:ok, events} = Store.stream(c.id, c.jido)
    assert Enum.to_list(events) == log
  end

  @tag obligation: "jido.agent_server.durable_turn.I2"
  test "workflow transitions hydrate the active frontier and keep history as references", c do
    {:ok, workflow} = Jido.Exec.compile(HydrationFlow, [])

    executed =
      workflow
      |> Runic.Workflow.enable_event_emission()
      |> Runic.Workflow.react_until_satisfied(Jido.Exec.Fact.local_value(%{value: 0}))

    events =
      (Runic.Workflow.build_log(executed) ++ Enum.reverse(executed.uncommitted_events))
      |> Enum.map(fn
        %Runic.Workflow.Events.FactProduced{} = event ->
          assert :ok = Store.save_fact(c.id, event.hash, event.value, c.jido)
          %{event | value: nil}

        event ->
          event
      end)

    assert {:ok, _batch_count} = Store.append(c.id, events, c.jido)

    assert {:ok, restored} =
             Store.update_workflow(c.jido, c.id, fn current -> {:ok, current} end)

    vertices = Map.values(restored.graph.vertices)
    assert Enum.any?(vertices, &is_struct(&1, Runic.Workflow.FactRef))
    assert Enum.any?(vertices, &is_struct(&1, Runic.Workflow.Fact))
    assert Jido.Exec.Result.project(restored) == {:ok, %{value: 2}}
  end

  @tag obligation: "jido.agent_server.durable_turn.I2"
  test "workflow transitions reject a missing frontier fact", c do
    {:ok, workflow} = Jido.Exec.compile(HydrationFlow, [])

    executed =
      workflow
      |> Runic.Workflow.enable_event_emission()
      |> Runic.Workflow.react_until_satisfied(Jido.Exec.Fact.local_value(%{value: 0}))

    events = Runic.Workflow.build_log(executed) ++ Enum.reverse(executed.uncommitted_events)

    detached =
      Enum.map(events, fn
        %Runic.Workflow.Events.FactProduced{} = event -> %{event | value: nil}
        event -> event
      end)

    required =
      detached
      |> Runic.Workflow.from_events(nil, fact_mode: :ref)
      |> Runic.Workflow.Rehydration.classify()
      |> Map.fetch!(:hot)

    missing =
      Enum.find(required, fn required_hash ->
        Enum.any?(events, &(event_hash(&1) == required_hash))
      end)

    assert missing

    Enum.each(events, fn
      %Runic.Workflow.Events.FactProduced{hash: ^missing} ->
        :ok

      %Runic.Workflow.Events.FactProduced{} = event ->
        assert :ok = Store.save_fact(c.id, event.hash, event.value, c.jido)

      _event ->
        :ok
    end)

    assert {:ok, _batch_count} = Store.append(c.id, detached, c.jido)

    assert {:error, :invalid_execution_checkpoint} =
             Store.update_workflow(c.jido, c.id, fn current -> {:ok, current} end)
  end

  @tag obligation: "jido.agent_server.durable_turn.I7"
  test "wait delivery rejects an execution with no saved graph", c do
    assert {:error, :missing_wait_checkpoint} =
             Runtime.accept_input(c.jido, c.id, c.config, %{
               id: "input",
               event: "event",
               payload: %{},
               wait_id: "wait"
             })
  end

  @tag obligation: "jido.agent_server.durable_turn.I2"
  test "execution identity isolates partitions, Agents, and command IDs", c do
    ids = [
      c.id,
      identity(%{c.init | partition: "south"}, "job"),
      identity(%{c.init | agent_id: "other"}, "job"),
      identity(c.init, "other")
    ]

    assert length(Enum.uniq(ids)) == 4

    for {id, index} <- Enum.with_index(ids) do
      assert :ok = Store.register(c.jido, id, c.config)
      assert {:ok, 1} = Store.append(id, [index], c.jido)
    end

    for {id, index} <- Enum.with_index(ids) do
      assert {:ok, events} = Store.stream(id, c.jido)
      assert Enum.to_list(events) == [index]
    end
  end

  @tag obligation: "jido.agent_server.durable_turn.I2"
  test "old runtime cleanup cannot remove or collect a replacement owner's checkpoint", c do
    assert {:ok, 1} = Store.append(c.id, [:replacement_graph], c.jido)
    owner = self()

    replacement =
      Task.async(fn ->
        assert :ok = Store.register(c.jido, c.id, c.config)
        send(owner, :registered)

        receive do
          :check -> Store.stream(c.id, c.jido)
        end
      end)

    assert_receive :registered
    assert {:error, :execution_owner_replaced} = Store.collect(c.jido, c.id)
    send(replacement.pid, :check)
    assert {:ok, events} = Task.await(replacement)
    assert Enum.to_list(events) == [:replacement_graph]
  end

  defp identity(init, id),
    do: {:jido_execution, Jido.Instance.NamespaceRegistry.namespace(init.jido), init.partition, init.agent_id, id}

  defp event_hash(%Runic.Workflow.Events.FactProduced{hash: hash}), do: hash
  defp event_hash(_event), do: nil

  defp large_session do
    %{
      id: "session-1",
      entries: [
        %{role: :user, content: String.duplicate("request ", 4_000)},
        %{role: :assistant, content: String.duplicate("response ", 4_000)}
      ]
    }
  end

  defp use_barrier_store(c, stage) do
    config =
      {BarrierBytes, store: c.store, barrier_owner: self(), barrier_stage: stage}

    assert :ok = Store.register(c.jido, c.id, config)
  end

  defp release_fact_barrier(stage, count) do
    blocked =
      for _index <- 1..count do
        assert_receive {:fact_cas_ready, ^stage, writer, key}, 1_000
        {writer, key}
      end

    Enum.each(blocked, fn {writer, key} ->
      send(writer, {:continue_fact_cas, stage, key})
    end)
  end

  defp execution_payloads(records) do
    for {key, bytes} <- records,
        String.ends_with?(key, ":prepared") or String.contains?(key, ":batches:") or
          (String.contains?(key, ":facts:") and not String.ends_with?(key, ":facts:index")),
        do: bytes
  end
end

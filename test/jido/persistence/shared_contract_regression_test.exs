defmodule Jido.Persistence.SharedContractRegressionTest do
  use Covenant.Case, component: "jido.persistence", async: false

  alias Jido.Agent.Address
  alias Jido.AgentServer.TurnResult
  alias Jido.Durable.Continuation
  alias Jido.Persistence
  alias Jido.Persistence.{Codec, Config, ETS, Inspector, NamespaceManifest, Record, Store, WakeStore}
  alias Jido.Test.AgentServer.Fixtures.CounterAgent
  alias Jido.Test.Persistence.CheckpointPortabilityProbe

  defmodule BarrierAdapter do
    @behaviour Store

    def validate_options(_opts), do: :ok

    def get("jido:agent:v3:" <> _ = key, opts) do
      result = ETS.get(key, Keyword.take(opts, [:table]))

      unless Process.get(:persistence_review_read) do
        Process.put(:persistence_review_read, true)
        send(Keyword.fetch!(opts, :observer), {:first_read, self()})

        receive do
          :continue -> :ok
        after
          2_000 -> raise "probe read barrier timed out"
        end
      end

      result
    end

    def get(key, opts), do: ETS.get(key, Keyword.take(opts, [:table]))

    def compare_and_swap(key, expected, value, opts),
      do: ETS.compare_and_swap(key, expected, value, Keyword.take(opts, [:table]))

    def delete(key, opts), do: ETS.delete(key, Keyword.take(opts, [:table]))
  end

  defmodule ScanAdapter do
    @behaviour Store
    def validate_options(_opts), do: :ok
    def get(_key, _opts), do: {:error, :not_found}
    def compare_and_swap(_key, _condition, _value, _opts), do: {:error, {:rejected, :probe}}
    def delete(_key, _opts), do: {:error, {:rejected, :probe}}
    def scan(_prefix, _cursor, _limit, opts), do: Keyword.fetch!(opts, :result)
  end

  setup do
    suffix = System.unique_integer([:positive])
    store = {ETS, table: :"persistence_review_store_#{suffix}"}
    instance = :"persistence_review_instance_#{suffix}"
    namespace = "persistence-review-#{suffix}"
    address = Address.new!(namespace: namespace, id: "review-agent")
    agent = CounterAgent.instantiate!(id: address.id)

    %{address: address, agent: agent, instance: instance, store: store}
  end

  @tag obligation: "jido.persistence.I9"
  test "JSON saves remain readable at the logical depth limit", c do
    depth = fn n -> Enum.reduce(1..n, 0, fn _, value -> %{box: value} end) end
    limit = depth.(100)
    assert {:ok, bytes} = Codec.JSON.encode(limit)
    assert {:ok, ^limit} = Codec.JSON.decode(bytes, [])
    assert {:error, {:persistence_json_limit, :depth}} = Codec.JSON.encode(depth.(101))

    mixed = %URI{scheme: "fixture", path: "/sample", query: [{:box, depth.(97)}]}
    assert {:ok, bytes} = Codec.JSON.encode(mixed)
    assert {:ok, ^mixed} = Codec.JSON.decode(bytes, [])

    profile = [store: c.store, codec: Codec.JSON]
    candidate = CheckpointPortabilityProbe.instantiate!(id: c.address.id, state: %{payload: depth.(45)})
    opts = [namespace: c.address.namespace]

    assert :ok = Persistence.save_agent(profile, candidate, opts)

    assert {:ok, ^candidate, 0} =
             Persistence.load_agent_with_revision(profile, CheckpointPortabilityProbe, c.address.id, opts)

    oversized = %{candidate | state: %{payload: depth.(101)}}

    assert {:error, {:persistence_json_limit, :depth}} =
             Persistence.save_agent(profile, oversized, opts ++ [revision: 1, expected_revision: 0])

    assert {:ok, ^candidate, 0} =
             Persistence.load_agent_with_revision(profile, CheckpointPortabilityProbe, c.address.id, opts)
  end

  @tag obligation: "jido.persistence.I15"
  test "default inspection and export keep saved Turn values behind explicit options", c do
    {:ok, config} = Config.open(c.store)
    signal = Jido.Signal.new!("turn.test", %{message: "synthetic-turn-marker"}, source: "/review")

    turn = %{
      id: "review-turn",
      status: :running,
      signal: signal,
      admitted_signal: signal,
      context: %{marker: "synthetic-context-marker"},
      plugin_inputs: %{sample: "synthetic-plugin-marker"},
      fingerprint: "fingerprint",
      expires_at: :infinity
    }

    assert :ok = Persistence.save_agent(config, c.agent, namespace: c.address.namespace, server_turn: turn)
    key = Persistence.agent_key(c.address)
    assert {:ok, result} = Inspector.read(config, key)
    assert result.checkpoint.agent.state == "[REDACTED]"
    assert result.server_turn.status == :running
    assert result.server_turn.id == "review-turn"

    markers = ["synthetic-turn-marker", "synthetic-context-marker", "synthetic-plugin-marker"]
    assert {:ok, full} = Inspector.read(config, key, full: true)

    for marker <- markers do
      refute inspect(result) =~ marker
      assert inspect(full) =~ marker
    end

    assert {:ok, io} = StringIO.open("")
    assert {:ok, 1} = Inspector.export_jsonl(config, "jido:agent:v3:", io)
    assert {_, output} = StringIO.contents(io)
    assert {:ok, full_io} = StringIO.open("")
    assert {:ok, 1} = Inspector.export_jsonl(config, "jido:agent:v3:", full_io, include_state: true)
    assert {_, full_output} = StringIO.contents(full_io)

    for marker <- markers do
      refute output =~ marker
      assert full_output =~ marker
    end

    reply = Jido.Signal.new!("turn.reply", %{message: "synthetic-reply-marker"}, source: "/review")

    result = %TurnResult{
      turn_id: turn.id,
      agent_address: c.address,
      agent_activation_id: "fixture-activation",
      status: :committed,
      durability: :durable,
      agent_revision: 1,
      persistence_revision: 1,
      completed_at: 1,
      reply: reply
    }

    terminal = Continuation.retain_result!(nil, result)

    handoff = Jido.Signal.new!("turn.handoff", %{message: "synthetic-handoff-marker"}, source: "/review")
    handoffs = %{outbox: [%{id: "fixture-handoff", to: c.address, signal: handoff}], accepted: %{}}

    assert :ok =
             Persistence.save_agent_runtime(
               config,
               c.agent,
               [namespace: c.address.namespace, revision: 1, expected_revision: 0, server_turn: terminal],
               handoffs
             )

    assert {:ok, %{server_turn: %{status: :completed}} = projected} = Inspector.read(config, key)
    assert projected.topology_handoffs == "[REDACTED]"
    assert {:ok, %{server_turn: %{terminal_result: %{reply: ^reply}}}} = Inspector.read(config, key, full: true)

    assert {:ok, terminal_io} = StringIO.open("")
    assert {:ok, 1} = Inspector.export_jsonl(config, "jido:agent:v3:", terminal_io)
    assert {_, terminal_output} = StringIO.contents(terminal_io)

    for marker <- ["synthetic-reply-marker", "synthetic-handoff-marker"] do
      refute inspect(projected) =~ marker
      refute terminal_output =~ marker
    end
  end

  @tag obligation: "jido.persistence.I1"
  test "direct Agent writes honor an existing namespace pin", c do
    {:ok, term} = Config.open(c.store)
    {:ok, json} = Config.open(store: c.store, codec: Codec.JSON)
    assert :ok = NamespaceManifest.open(term, c.address.namespace)
    opts = [namespace: c.address.namespace]

    operations = [
      fn -> Persistence.save_agent(json, c.agent, opts) end,
      fn -> Persistence.create_agent(json, c.agent, opts) end,
      fn -> Persistence.delete_agent(json, CounterAgent, c.address.id, opts) end,
      fn -> Persistence.upgrade_agent(json, CounterAgent, c.address.id, CounterAgent, opts) end
    ]

    for operation <- operations do
      assert {:error, {:persistence_namespace_mismatch, _, _}} = operation.()
      assert {:error, :not_found} = Store.read(c.store, Persistence.agent_key(c.address))
    end

    assert :ok = Persistence.save_agent(term, c.agent, opts)
    assert {:ok, _agent} = Persistence.load_agent(term, CounterAgent, c.address.id, opts)
  end

  @tag obligation: "jido.persistence.I1"
  test "the first direct write pins a new namespace before later instance startup", c do
    {:ok, term} = Config.open(c.store)
    {:ok, json} = Config.open(store: c.store, codec: Codec.JSON)

    assert :ok = Persistence.save_agent(json, c.agent, namespace: c.address.namespace)
    assert {:ok, %{codec: %{id: "jido.json"}}} = NamespaceManifest.read(json, c.address.namespace)
    assert {:error, {:persistence_namespace_mismatch, _, _}} = NamespaceManifest.open(term, c.address.namespace)
  end

  @tag obligation: "jido.persistence.I1"
  test "instance startup and a direct write agree on one codec", c do
    {ETS, opts} = c.store
    barrier = {BarrierAdapter, Keyword.put(opts, :observer, self())}
    json = [store: barrier, codec: Codec.JSON]
    write = Task.async(fn -> Persistence.save_agent(json, c.agent, namespace: c.address.namespace) end)
    assert_receive {:first_read, reader}, 2_000

    start_supervised!({Jido, name: c.instance, namespace: c.address.namespace, persistence: c.store})
    send(reader, :continue)
    assert {:error, {:persistence_namespace_mismatch, _, _}} = Task.await(write)
    assert {:error, :not_found} = Store.read(c.store, Persistence.agent_key(c.address))
  end

  @tag obligation: "jido.persistence.I15"
  test "Store rejects malformed scan pages" do
    invalid = [
      {:ok, :bad_entries, nil},
      {:ok, [{"other:key", "bytes"}], nil},
      {:ok, [{"jido:1", 1}], nil},
      {:ok, [{:atom, "bytes"}], nil},
      {:ok, [{"jido:1", "1"}, {"jido:2", "2"}], nil},
      {:ok, [], "same"},
      {:ok, [], :bad_cursor}
    ]

    for result <- invalid do
      opts = [cursor: "same", limit: 1]
      assert {:ok, store} = Store.open({ScanAdapter, result: result})

      assert {:error, %Jido.Error.ExecutionError{details: %{operation: :scan}}} =
               Store.scan(store, "jido:", opts)
    end

    assert {:ok, store} = Store.open({ScanAdapter, result: {:ok, [], "next"}})
    assert {:ok, [], "next"} = Store.scan(store, "jido:", cursor: "same")
  end

  @tag obligation: "jido.persistence.I13"
  test "Address delete preserves a concurrent revision written after its first read", c do
    {ETS, opts} = c.store
    source = {BarrierAdapter, Keyword.put(opts, :observer, self())}
    start_supervised!({Jido, name: c.instance, namespace: c.address.namespace, persistence: source})
    assert :ok = Persistence.save_agent(c.store, c.agent, namespace: c.address.namespace, revision: 1)

    deleting = Task.async(fn -> Jido.delete_agent(c.instance, c.address) end)
    assert_receive {:first_read, reader}, 2_000

    assert :ok =
             Persistence.save_agent(c.store, c.agent, namespace: c.address.namespace, expected_revision: 1, revision: 2)

    send(reader, :continue)
    assert {:error, :conflict} = Task.await(deleting, 1_500)

    assert {:ok, _, 2} =
             Persistence.load_agent_with_revision(c.store, CounterAgent, c.address.id, namespace: c.address.namespace)

    assert :ok = Persistence.delete_agent_address(c.store, c.address)
    assert :ok = Persistence.delete_agent_address(c.store, c.address)
    assert {:ok, bytes, _} = Store.read(c.store, Persistence.agent_key(c.address))
    assert {:ok, %{kind: :tombstone, rev: 3, agent_rev: 2}} = Record.decode(bytes)
    assert {:error, :not_found} = Persistence.delete_agent_address(c.store, %{c.address | id: "missing"})
  end

  @tag obligation: "jido.persistence.I17"
  test "wake recovery reports a missing or stale indexed shard", c do
    start_supervised!({Jido, name: c.instance, namespace: c.address.namespace, persistence: c.store})
    deadline = System.system_time(:millisecond) + 120_000
    entry = %{agent_address: c.address, turn_id: "review-turn", wait_id: "review-wait", deadline: deadline}

    assert :ok = WakeStore.put(c.instance, [entry])
    assert {:ok, [^entry]} = WakeStore.list(c.instance)
    assert {:ok, entries, nil} = Store.scan(c.store, "jido:wake:v3:")
    {key, bytes} = Enum.find(entries, fn {key, _} -> String.contains?(key, ":shard:") end)
    assert :ok = Store.delete(c.store, key)
    assert {:error, {:wake_shard_behind_index, _, _, 1, 0}} = WakeStore.list(c.instance)

    assert :ok = Store.compare_and_swap(c.store, key, :not_found, bytes)
    next = %{entry | deadline: deadline + 1}
    assert :ok = WakeStore.put(c.instance, [next])
    assert {:ok, current, condition} = Store.read(c.store, key)
    assert :ok = Store.compare_and_swap(c.store, key, condition, bytes)
    assert {:error, {:wake_shard_behind_index, _, _, 2, 1}} = WakeStore.list(c.instance)
    assert {:ok, ^bytes, condition} = Store.read(c.store, key)
    assert :ok = Store.compare_and_swap(c.store, key, condition, current)
    assert {:ok, [^entry, ^next]} = WakeStore.list(c.instance)

    {:ok, config} = Config.open(c.store)
    assert {:ok, shard} = Config.decode(config, current)
    assert {:ok, empty} = Config.encode(config, %{shard | generation: 3, entries: []})
    assert {:ok, ^current, condition} = Store.read(c.store, key)
    assert :ok = Store.compare_and_swap(c.store, key, condition, empty)
    assert {:ok, []} = WakeStore.list(c.instance)
  end
end

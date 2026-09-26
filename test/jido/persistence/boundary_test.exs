defmodule Jido.Persistence.BoundaryTest do
  use ExUnit.Case, async: true

  alias Jido.Agent
  alias Jido.Agent.Checkpoint
  alias Jido.Persistence
  alias Jido.Persistence.{ETS, Record}
  alias JidoTest.AgentFixtures.CounterAgent, as: Basic

  defmodule ReadAdapter do
    @behaviour Jido.Persistence.Adapter
    def get(key, opts), do: Keyword.fetch!(opts, :read).(key)
    def compare_and_swap(_key, _expected, _value, _opts), do: flunk("unexpected storage write")
  end

  defmodule RecordingAdapter do
    @behaviour Jido.Persistence.Adapter

    def validate_options(opts) do
      send(Keyword.fetch!(opts, :observer), {:adapter_call, :validate_options})
      ETS.validate_options(opts)
    end

    def get(key, opts) do
      send(Keyword.fetch!(opts, :observer), {:adapter_call, {:get, key}})
      ETS.get(key, opts)
    end

    def compare_and_swap(key, expected, value, opts) do
      send(Keyword.fetch!(opts, :observer), {:adapter_call, {:cas, key, expected, value}})
      ETS.compare_and_swap(key, expected, value, opts)
    end
  end

  defmodule Custom do
    use Jido.Agent, name: "custom_boundary"
    def checkpoint(agent, _context), do: {:ok, %{id: agent.id}}
    def restore(%{id: id}, _context), do: new(id: id)
  end

  setup do
    agent = Basic.new!(id: "record-boundary")
    store = {ETS, table: :"record_boundary_#{System.unique_integer([:positive])}"}
    %{agent: agent, store: store}
  end

  test "the key contains only the exact Ref tuple", c do
    ref = Agent.Ref.new!(namespace: "record-boundary", partition: "blue", id: c.agent.id)
    assert "jido:agent:v1:" <> encoded = Persistence.agent_key(ref)

    assert {ref.namespace, ref.partition, ref.id} ==
             encoded |> Base.url_decode64!(padding: false) |> :erlang.binary_to_term([:safe])
  end

  test "stored envelopes reject invalid fields without changing their bytes", c do
    namespace = "record-boundary"
    assert :ok = Persistence.save_agent(c.store, c.agent, namespace: namespace)
    ref = Agent.Ref.new!(namespace: namespace, id: c.agent.id)
    key = Persistence.agent_key(ref)
    {ETS, opts} = c.store
    {:ok, original} = ETS.get(key, opts)
    {:ok, record} = Record.decode(original)

    for {field, value} <- [
          namespace: "other",
          kind: :unknown,
          checkpoint: nil,
          checkpoint: %URI{},
          agent_vsn: 0,
          agent_vsn: "1",
          revision: -1
        ] do
      {:ok, bytes} = Record.encode(Map.put(record, field, value))
      assert :ok = ETS.put(key, bytes, opts)

      assert {:error, {:invalid_persistence_record, ^field}} =
               Persistence.load_agent(c.store, Basic, c.agent.id, namespace: namespace)

      assert {:ok, ^bytes} = ETS.get(key, opts)
    end

    assert Record.decode(nil) == {:error, :invalid_persistence_record}

    assert Record.validate(nil, ref, Basic) == {:error, {:invalid_persistence_record, :shape}}

    assert Record.validate(%{record | format: 2}, ref, Basic) ==
             {:error, {:invalid_persistence_record, :format}}

    assert Record.kind(%{format: 99}) == :unknown
  end

  test "identity validation preserves scope-first error order and exact key sets", c do
    {:ok, checkpoint} = Agent.checkpoint(c.agent)

    ref = Agent.Ref.new!(namespace: "first", partition: "blue", id: c.agent.id)
    {:ok, active} = Record.build_active(c.agent, ref, 0, checkpoint)
    tombstone = active |> Map.drop([:agent_vsn, :checkpoint]) |> Map.put(:kind, :tombstone)

    changes = [
      {:namespace, "other"},
      {:agent_module, String},
      {:agent_id, "other"},
      {:partition, "other"}
    ]

    for record <- [active, tombstone] do
      assert :ok = Record.validate(record, ref, Basic)

      for {{field, _value}, index} <- Enum.with_index(changes) do
        changed = Map.merge(record, Map.new(Enum.drop(changes, index)))

        assert {:error, {:invalid_persistence_record, ^field}} =
                 Record.validate(changed, ref, Basic)
      end

      for key <- Map.keys(record) do
        field = if key in [:format, :kind], do: key, else: :shape

        assert {:error, {:invalid_persistence_record, ^field}} =
                 Record.validate(Map.delete(record, key), ref, Basic)

        # Equal size alone does not prove an exact key set.
        changed = record |> Map.delete(key) |> Map.put(:extra, true)

        assert {:error, {:invalid_persistence_record, ^field}} =
                 Record.validate(changed, ref, Basic)
      end

      assert {:error, {:invalid_persistence_record, :shape}} =
               Record.validate(Map.put(record, :extra, true), ref, Basic)
    end
  end

  test "identity setup preserves adapter call order and exact stored bytes", c do
    {:ok, checkpoint} = Agent.checkpoint(c.agent)
    {ETS, adapter_opts} = c.store
    store = {RecordingAdapter, Keyword.put(adapter_opts, :observer, self())}

    namespace = "record-sequence"
    opts = [instance: :record_instance, partition: "blue", namespace: namespace]
    ref = Agent.Ref.new!(namespace: namespace, partition: "blue", id: c.agent.id)
    key = Persistence.agent_key(ref)

    record =
      %{
        format: 3,
        namespace: namespace,
        kind: :active,
        agent_module: Basic,
        agent_vsn: c.agent.vsn,
        agent_id: c.agent.id,
        partition: "blue",
        revision: 0,
        checkpoint: checkpoint
      }

    created = :erlang.term_to_binary(record)
    updated = :erlang.term_to_binary(%{record | revision: 1})

    tombstone =
      record
      |> Map.drop([:agent_vsn, :checkpoint])
      |> Map.merge(%{kind: :tombstone, revision: 1})

    deleted = :erlang.term_to_binary(tombstone)
    prefix = [:validate_options]

    # Initial revision validation precedes storage access.
    assert {:error, {:invalid_initial_revision, 1}} =
             Persistence.create_agent(store, c.agent, Keyword.put(opts, :revision, 1))

    assert adapter_calls() == [:validate_options]

    assert :ok = Persistence.create_agent(store, c.agent, opts)
    assert adapter_calls() == prefix ++ [{:cas, key, :not_found, created}]

    assert :ok =
             Persistence.save_agent(store, c.agent, opts ++ [revision: 1, expected_revision: 0])

    assert adapter_calls() == prefix ++ [{:get, key}, {:cas, key, created, updated}]

    assert {:ok, restored, 1} =
             Persistence.load_agent_with_revision(store, Basic, c.agent.id, opts)

    assert restored == c.agent
    assert adapter_calls() == prefix ++ [{:get, key}]

    assert :ok = Persistence.delete_agent(store, Basic, c.agent.id, opts)
    assert adapter_calls() == prefix ++ [{:get, key}, {:cas, key, updated, deleted}]
    assert {:ok, ^deleted} = ETS.get(key, adapter_opts)
  end

  test "replacement requires a stable identity and an existing Ref record", c do
    target = c.agent

    assert {:error, :stable_namespace_required} =
             Persistence.replace_agent(c.store, c.agent, target)

    assert {:error, :agent_identity_mismatch} =
             Persistence.replace_agent(c.store, c.agent, %{target | id: "other"})

    empty = {ReadAdapter, read: fn _ -> {:error, :not_found} end}

    assert {:error, :conflict} =
             Persistence.replace_agent(empty, c.agent, target, namespace: "missing")

    assert {:error, {:invalid_initial_revision, 1}} =
             Persistence.create_agent(c.store, c.agent, revision: 1)
  end

  test "missing namespaces and removed write gates fail before storage access", c do
    store = {ReadAdapter, read: fn _ -> flunk("unexpected storage read") end}

    for call <- [
          &Persistence.save_agent(store, c.agent, &1),
          &Persistence.create_agent(store, c.agent, &1),
          &Persistence.replace_agent(store, c.agent, c.agent, &1),
          &Persistence.load_agent(store, Basic, c.agent.id, &1),
          &Persistence.delete_agent(store, Basic, c.agent.id, &1)
        ] do
      assert {:error, :stable_namespace_required} = call.([])
      assert {:error, :stable_namespace_required} = call.(namespace: nil)

      for invalid <- ["", :namespace, 42] do
        assert {:error, %Jido.Error.ValidationError{}} = call.(namespace: invalid)
      end

      for invalid <- [:blue, 1, ""] do
        assert {:error, %Jido.Error.ValidationError{}} =
                 call.(namespace: "valid", partition: invalid)
      end

      assert {:error, {:unsupported_persistence_option, :write_authority}} =
               call.(namespace: "valid", write_authority: nil)
    end
  end

  test "failed storage reads cannot become writes", c do
    failing = {ReadAdapter, read: fn _ -> {:error, :offline} end}
    opts = [namespace: "read-fault"]
    assert {:error, :offline} = Persistence.load_agent(failing, Basic, c.agent.id, opts)
    assert {:error, :offline} = Persistence.save_agent(failing, c.agent, opts)
    assert {:error, :offline} = Persistence.replace_agent(failing, c.agent, c.agent, opts)
    assert {:error, :offline} = Persistence.delete_agent(failing, Basic, c.agent.id, opts)
  end

  test "checkpoint public boundaries reject non-map input and context", c do
    {:ok, checkpoint} = Agent.checkpoint(c.agent)

    for invalid <- [nil, [], %URI{}] do
      assert {:error, %Jido.Error.ValidationError{}} = Agent.checkpoint(c.agent, invalid)
      assert {:error, %Jido.Error.ValidationError{}} = Agent.restore(Basic, checkpoint, invalid)
      assert {:error, %Jido.Error.ValidationError{}} = Agent.restore(Basic, invalid)

      assert {:error, %Jido.Error.ValidationError{}} =
               Checkpoint.default_restore(Basic, invalid, %{})

      assert {:error, %Jido.Error.ValidationError{}} = Checkpoint.default_checkpoint(invalid, %{})
    end

    assert {:error, %{details: %{code: :invalid_checkpoint}}} =
             Agent.restore(Basic, Map.put(checkpoint, :unknown, true))

    assert {:error, %{details: %{code: :invalid_checkpoint}}} =
             Agent.restore(String, %{checkpoint | agent_module: String})

    assert Persistence.portable_term?(%{nested: [1, "two"]})
    refute Persistence.portable_term?(%{nested: self()})
  end

  test "custom and embedded checkpoints reject changed headers and payloads" do
    custom = Custom.new!(id: "custom")
    {:ok, checkpoint} = Agent.checkpoint(custom)

    for changed <- [
          %{checkpoint | payload: nil},
          %{checkpoint | payload: %URI{}},
          %{checkpoint | agent_module: Basic},
          %{checkpoint | vsn: -1},
          Map.put(checkpoint, :unknown, true)
        ] do
      assert {:error, %{details: %{code: :invalid_checkpoint}}} = Agent.restore(Custom, changed)
    end

    assert {:error, %{details: %{code: :invalid_checkpoint}}} =
             Agent.restore(Basic, %{checkpoint | agent_module: Basic})

    definition = Agent.new!(name: "embedded", vsn: 1)
    embedded = Agent.instantiate!(definition, id: "embedded")
    {:ok, saved} = Agent.checkpoint(embedded)

    assert {:error, %{details: %{code: :definition_mismatch}}} =
             Agent.restore(Agent, %{saved | definition: %{definition | vsn: 2}})
  end

  # Each operation has returned before this mailbox snapshot. This does not
  # wait for asynchronous completion.
  defp adapter_calls(acc \\ []) do
    receive do
      {:adapter_call, call} -> adapter_calls([call | acc])
    after
      0 -> Enum.reverse(acc)
    end
  end
end

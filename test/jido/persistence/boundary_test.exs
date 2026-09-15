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

    assert Record.validate(nil, nil, Basic, c.agent.id, nil) ==
             {:error, {:invalid_persistence_record, :shape}}

    assert Record.validate_ref(nil, namespace, Basic, c.agent.id, nil) ==
             {:error, {:invalid_persistence_record, :shape}}

    assert Record.validate_ref(%{record | format: 2}, namespace, Basic, c.agent.id, nil) ==
             {:error, {:invalid_persistence_record, :format}}

    assert Record.kind(%{format: 99}) == :unknown

    assert Record.validate(%{format: 1, kind: :unknown}, nil, Basic, c.agent.id, nil) ==
             {:error, {:invalid_persistence_record, :kind}}
  end

  test "legacy records cannot cross instance boundaries", c do
    assert {:ok, checkpoint} = Agent.checkpoint(c.agent)
    assert {:ok, record} = Record.build_active(c.agent, :first, nil, 0, checkpoint)

    assert Record.validate(record, :second, Basic, c.agent.id, nil) ==
             {:error, {:invalid_persistence_record, :instance}}
  end

  test "identity validation preserves scope-first error order and exact key sets", c do
    {:ok, checkpoint} = Agent.checkpoint(c.agent)

    for {scope, value, build, validate} <- [
          {:instance, :first, &Record.build_active/5, &Record.validate/5},
          {:namespace, "first", &Record.build_ref_active/5, &Record.validate_ref/5}
        ] do
      {:ok, active} = build.(c.agent, value, "blue", 0, checkpoint)
      tombstone = active |> Map.drop([:agent_vsn, :checkpoint]) |> Map.put(:kind, :tombstone)

      changes = [
        {scope, "other"},
        {:agent_module, String},
        {:agent_id, "other"},
        {:partition, "other"}
      ]

      for record <- [active, tombstone] do
        assert :ok = validate.(record, value, Basic, c.agent.id, "blue")

        for {{field, _value}, index} <- Enum.with_index(changes) do
          changed = Map.merge(record, Map.new(Enum.drop(changes, index)))

          assert {:error, {:invalid_persistence_record, ^field}} =
                   validate.(changed, value, Basic, c.agent.id, "blue")
        end

        for key <- Map.keys(record) do
          field = if key in [:format, :kind], do: key, else: :shape

          assert {:error, {:invalid_persistence_record, ^field}} =
                   validate.(Map.delete(record, key), value, Basic, c.agent.id, "blue")

          # Equal size alone does not prove an exact key set.
          changed = record |> Map.delete(key) |> Map.put(:extra, true)

          assert {:error, {:invalid_persistence_record, ^field}} =
                   validate.(changed, value, Basic, c.agent.id, "blue")
        end

        assert {:error, {:invalid_persistence_record, :shape}} =
                 validate.(Map.put(record, :extra, true), value, Basic, c.agent.id, "blue")
      end
    end
  end

  test "identity setup preserves adapter call order and exact stored bytes", c do
    {:ok, checkpoint} = Agent.checkpoint(c.agent)
    {ETS, adapter_opts} = c.store
    store = {RecordingAdapter, Keyword.put(adapter_opts, :observer, self())}

    for namespace <- [nil, "record-sequence"] do
      opts = [instance: :record_instance, partition: "blue", namespace: namespace]
      legacy_key = Persistence.agent_key(:record_instance, Basic, c.agent.id, "blue")

      {key, probes, scope, value} =
        if namespace do
          ref = Agent.Ref.new!(namespace: namespace, partition: "blue", id: c.agent.id)
          key = Persistence.agent_key(ref)
          {key, [{:get, key}, {:get, legacy_key}], :namespace, namespace}
        else
          {legacy_key, [], :instance, :record_instance}
        end

      record =
        %{
          format: if(namespace, do: 3, else: 2),
          kind: :active,
          agent_module: Basic,
          agent_vsn: c.agent.vsn,
          agent_id: c.agent.id,
          partition: "blue",
          revision: 0,
          checkpoint: checkpoint
        }
        |> Map.put(scope, value)

      created = :erlang.term_to_binary(record)
      updated = :erlang.term_to_binary(%{record | revision: 1})

      tombstone =
        record
        |> Map.drop([:agent_vsn, :checkpoint])
        |> Map.merge(%{kind: :tombstone, revision: 1})

      deleted = :erlang.term_to_binary(tombstone)
      prefix = [:validate_options] ++ probes

      # Initial revision validation still precedes either identity read.
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

      # Do not leave a compatible record for the next iteration.
      assert :ok = ETS.delete(key, adapter_opts)
    end
  end

  test "replacement requires a stable identity and an existing Ref record", c do
    target = c.agent

    assert {:error, :stable_namespace_required} =
             Persistence.replace_agent(c.store, c.agent, target)

    assert :ok = Persistence.save_agent(c.store, c.agent)

    assert {:error, :stable_namespace_required} =
             Persistence.replace_agent(c.store, c.agent, target, namespace: "legacy")

    assert {:error, :agent_identity_mismatch} =
             Persistence.replace_agent(c.store, c.agent, %{target | id: "other"})

    empty = {ReadAdapter, read: fn _ -> {:error, :not_found} end}

    assert {:error, :conflict} =
             Persistence.replace_agent(empty, c.agent, target, namespace: "missing")

    assert {:error, {:invalid_initial_revision, 1}} =
             Persistence.create_agent(c.store, c.agent, revision: 1)
  end

  test "failed storage reads cannot become writes or successful identity resolution", c do
    namespace = "read-fault"
    ref = Agent.Ref.new!(namespace: namespace, id: c.agent.id)
    ref_key = Persistence.agent_key(ref)
    legacy_key = Persistence.agent_key(nil, Basic, c.agent.id)

    for failed_key <- [ref_key, legacy_key] do
      store =
        {ReadAdapter,
         read: fn key ->
           if key == failed_key, do: {:error, :offline}, else: {:error, :not_found}
         end}

      assert {:error, :offline} =
               Persistence.load_agent(store, Basic, c.agent.id, namespace: namespace)
    end

    failing = {ReadAdapter, read: fn _ -> {:error, :offline} end}
    assert {:error, :offline} = Persistence.save_agent(failing, c.agent)

    Process.put(:replacement_reads, 0)

    intermittent =
      {ReadAdapter,
       read: fn _ ->
         count = Process.get(:replacement_reads) + 1
         Process.put(:replacement_reads, count)
         if count < 3, do: {:error, :not_found}, else: {:error, :offline}
       end}

    assert {:error, :offline} =
             Persistence.replace_agent(intermittent, c.agent, c.agent, namespace: namespace)

    assert Process.get(:replacement_reads) == 3
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

defmodule Jido.Persistence.BoundaryTest do
  use Covenant.Case, component: "jido.persistence", async: true

  alias Jido.Agent
  alias Jido.Persistence.AgentCheckpoint, as: Checkpoint
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
    def restore(%{id: id}, _context), do: instantiate(id: id)
  end

  defmodule ContextAgent do
    use Jido.Agent, name: "persistence_context_boundary"

    def checkpoint(agent, context) do
      notify(context, {:checkpoint_context, context})

      case context[:mode] do
        :error -> {:error, :checkpoint_rejected}
        :invalid -> :invalid
        :raise -> raise "checkpoint failed"
        :throw -> throw(:checkpoint_failed)
        :exit -> exit(:checkpoint_failed)
        _ -> {:ok, %{id: agent.id}}
      end
    end

    def restore(%{id: id}, context) do
      notify(context, {:restore_context, context})

      case context[:mode] do
        :error -> {:error, :restore_rejected}
        :invalid -> :invalid
        :raise -> raise "restore failed"
        :throw -> throw(:restore_failed)
        :exit -> exit(:restore_failed)
        _ -> instantiate(id: id)
      end
    end

    defp notify(context, message) do
      if observer = context[:observer], do: send(observer, message)
      if instance = context[:instance], do: send(instance, message)
    end
  end

  setup do
    agent = Basic.instantiate!(id: "record-boundary")
    store = {ETS, table: :"record_boundary_#{System.unique_integer([:positive])}"}
    %{agent: agent, store: store}
  end

  @tag obligation: "jido.persistence.I2"
  test "the key contains only the exact Ref tuple", c do
    ref = Agent.Ref.new!(namespace: "record-boundary", partition: "blue", id: c.agent.id)
    assert "jido:agent:v1:" <> encoded = Persistence.agent_key(ref)

    assert {ref.namespace, ref.partition, ref.id} ==
             encoded |> Base.url_decode64!(padding: false) |> :erlang.binary_to_term([:safe])

    for id <- ["a", "ab", "abc"] do
      ref = Agent.Ref.new!(namespace: "key", partition: nil, id: id)
      expected = :erlang.term_to_binary({ref.namespace, ref.partition, ref.id})
      expected = Base.url_encode64(expected, padding: false)
      assert Persistence.agent_key(ref) == "jido:agent:v1:" <> expected
    end
  end

  @tag obligation: "jido.persistence.I5"
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
          vsn: nil,
          vsn: 0,
          vsn: "1",
          rev: -1
        ] do
      {:ok, bytes} = Record.encode(Map.put(record, field, value))
      assert :ok = ETS.put(key, bytes, opts)

      assert {:error, {:invalid_persistence_record, ^field}} =
               Persistence.load_agent(c.store, Basic, c.agent.id, namespace: namespace)

      assert {:ok, ^bytes} = ETS.get(key, opts)
    end

    assert Record.decode(nil) == {:error, :invalid_persistence_record}

    atom_name = "jido_persistence_unknown_#{System.unique_integer([:positive])}"
    encoded_atom = <<131, 118, byte_size(atom_name)::16, atom_name::binary>>
    assert Record.decode(encoded_atom) == {:error, :invalid_persistence_record}

    assert Record.validate(nil, ref, Basic) == {:error, {:invalid_persistence_record, :shape}}

    assert Record.validate(%{record | fmt: 2}, ref, Basic) ==
             {:error, {:invalid_persistence_record, :fmt}}

    for vsn <- [nil, 0, "1"] do
      assert Record.validate(%{record | vsn: vsn}, ref, Basic) ==
               {:error, {:invalid_persistence_record, :vsn}}
    end

    assert Record.kind(%{format: 99}) == :unknown
    assert Record.kind(%{fmt: 4, kind: :active}) == :active
    assert Record.kind(%{format: 3, kind: :tombstone}) == :tombstone
    assert Record.kind(%{kind: :active}) == :unknown
    assert Record.kind(%{fmt: 4, kind: :unknown}) == :unknown
    assert Record.kind(%{fmt: 4, kind: :future}) == :unknown
    assert Record.kind(%{format: 3, kind: :future}) == :unknown
    assert Record.kind(%{fmt: 3, kind: :active}) == :unknown

    assert Record.require_active(%{}) == {:error, {:invalid_persistence_record, :kind}}
    assert Record.require_active_for_write(%{}) == {:error, {:invalid_persistence_record, :kind}}
  end

  @tag obligation: ["jido.persistence.I5", "jido.persistence.I12"]
  test "durable Turn data has one exact portable record shape", c do
    ref = Agent.Ref.new!(namespace: "record-boundary", id: c.agent.id)
    {:ok, checkpoint} = Persistence.snapshot(c.agent)
    signal = Jido.Signal.new!("turn.test", %{}, source: "/contract")

    turn = %{
      id: "turn-1",
      status: :running,
      signal: signal,
      admitted_signal: signal,
      context: %{},
      plugin_inputs: %{},
      fingerprint: "fingerprint",
      expires_at: :infinity
    }

    for status <- [:running, :completed, :failed, :cancelled] do
      candidate = %{turn | status: status}
      assert {:ok, record} = Record.build_active(c.agent, ref, 0, checkpoint, candidate)
      assert record.server_turn === candidate
      assert :ok = Record.validate(record, ref, Basic)
    end

    assert {:ok, _record} =
             Record.build_active(c.agent, ref, 0, checkpoint, %{turn | id: "x"})

    invalid = [
      %{turn | id: ""},
      %{turn | status: :unknown},
      %{turn | signal: %{}},
      %{turn | admitted_signal: %{}},
      %{turn | context: []},
      %{turn | plugin_inputs: []},
      %{turn | fingerprint: nil},
      %{turn | expires_at: nil},
      Map.delete(turn, :context),
      Map.put(turn, :extra, true)
    ]

    for candidate <- invalid do
      assert {:error, {:invalid_persistence_record, :server_turn}} =
               Record.build_active(c.agent, ref, 0, checkpoint, candidate)
    end
  end

  @tag obligation: ["jido.persistence.I2", "jido.persistence.I5"]
  test "identity validation preserves scope-first error order and exact key sets", c do
    {:ok, checkpoint} = Jido.Persistence.snapshot(c.agent)

    ref = Agent.Ref.new!(namespace: "first", partition: "blue", id: c.agent.id)
    {:ok, active} = Record.build_active(c.agent, ref, 0, checkpoint)
    tombstone = active |> Map.drop([:vsn, :checkpoint]) |> Map.put(:kind, :tombstone)

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
        field =
          case key do
            :fmt -> :format
            :kind -> :kind
            _ -> :shape
          end

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

  @tag obligation: [
         "jido.persistence.I2",
         "jido.persistence.I5",
         "jido.persistence.I12",
         "jido.persistence.I13"
       ]
  test "identity setup preserves adapter call order and exact stored bytes", c do
    {:ok, checkpoint} = Jido.Persistence.snapshot(c.agent)
    {ETS, adapter_opts} = c.store
    store = {RecordingAdapter, Keyword.put(adapter_opts, :observer, self())}

    namespace = "record-sequence"
    opts = [instance: :record_instance, partition: "blue", namespace: namespace]
    ref = Agent.Ref.new!(namespace: namespace, partition: "blue", id: c.agent.id)
    key = Persistence.agent_key(ref)

    record =
      %{
        fmt: 4,
        namespace: namespace,
        kind: :active,
        agent_module: Basic,
        vsn: c.agent.vsn,
        agent_id: c.agent.id,
        partition: "blue",
        rev: 0,
        checkpoint: checkpoint
      }

    created = :erlang.term_to_binary(record)
    updated = :erlang.term_to_binary(%{record | rev: 1})

    tombstone =
      record
      |> Map.drop([:vsn, :checkpoint])
      |> Map.merge(%{kind: :tombstone, rev: 1})

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

  @tag obligation: "jido.persistence.I12"
  test "revision checks accept only one valid predecessor", c do
    opts = [namespace: "revision-check"]
    assert :ok = Persistence.save_agent(c.store, c.agent, opts)
    assert :ok = Persistence.save_agent(c.store, c.agent, opts)

    changed = %{c.agent | state: %{c.agent.state | count: 1}}
    assert {:error, :conflict} = Persistence.save_agent(c.store, changed, opts)

    assert :ok =
             Persistence.save_agent(c.store, changed,
               namespace: "revision-check",
               revision: 1,
               expected_revision: 0
             )

    for expected <- [-1, :invalid] do
      assert {:error, {:invalid_expected_revision, ^expected}} =
               Persistence.save_agent(c.store, changed,
                 namespace: "revision-check",
                 revision: 2,
                 expected_revision: expected
               )
    end

    assert {:error, :conflict} =
             Persistence.save_agent(c.store, changed,
               namespace: "revision-check",
               revision: 2,
               expected_revision: 0
             )

    assert {:error, :conflict} =
             Persistence.save_agent(c.store, c.agent,
               namespace: "revision-check",
               revision: 0
             )

    missing = %{c.agent | id: "missing-predecessor"}

    assert {:error, :conflict} =
             Persistence.save_agent(c.store, missing,
               namespace: "revision-check",
               revision: 1,
               expected_revision: 1
             )

    initial = %{c.agent | id: "initial-predecessor"}

    assert :ok =
             Persistence.save_agent(c.store, initial,
               namespace: "revision-check",
               revision: 0,
               expected_revision: 0
             )

    for revision <- [-1, :invalid] do
      invalid = %{c.agent | id: "invalid-revision-#{inspect(revision)}"}

      assert {:error, {:invalid_checkpoint, :shape}} =
               Persistence.save_agent(c.store, invalid,
                 namespace: "revision-check",
                 revision: revision
               )
    end
  end

  @tag obligation: ["jido.persistence.I1", "jido.persistence.I2", "jido.persistence.I12"]
  test "missing namespaces and removed write gates fail before storage access", c do
    store = {ReadAdapter, read: fn _ -> flunk("unexpected storage read") end}

    for call <- [
          &Persistence.save_agent(store, c.agent, &1),
          &Persistence.create_agent(store, c.agent, &1),
          &Persistence.load_agent(store, Basic, c.agent.id, &1),
          &Persistence.delete_agent(store, Basic, c.agent.id, &1)
        ] do
      assert {:error, :stable_namespace_required} = call.([])
      assert {:error, :stable_namespace_required} = call.(namespace: nil)

      for invalid <- ["", :namespace, 42] do
        assert {:error, %{__exception__: true}} = call.(namespace: invalid)
      end

      for invalid <- [:blue, 1, ""] do
        assert {:error, %{__exception__: true}} =
                 call.(namespace: "valid", partition: invalid)
      end

      assert {:error, {:unsupported_persistence_option, :write_authority}} =
               call.(namespace: "valid", write_authority: nil)
    end
  end

  @tag obligation: "jido.persistence.I12"
  test "public operations reject invalid Agent and identity input", c do
    assert {:error,
            %Jido.Error.ValidationError{
              details: %{operation: :save_agent, agent: :not_an_agent}
            }} = Persistence.save_agent(c.store, :not_an_agent, namespace: "input")

    for {operation, call} <- [
          {:load_agent, &Persistence.load_agent(c.store, :not_a_module, 1, &1)},
          {:load_agent_with_revision,
           &Persistence.load_agent_with_revision(c.store, :not_a_module, 1, &1)},
          {:delete_agent, &Persistence.delete_agent(c.store, :not_a_module, 1, &1)}
        ] do
      assert {:error,
              %Jido.Error.ValidationError{
                details: %{
                  operation: ^operation,
                  agent_module: :not_a_module,
                  agent_id: 1
                }
              }} = call.(namespace: "input")
    end
  end

  @tag obligation: ["jido.persistence.I3", "jido.persistence.I12", "jido.persistence.I13"]
  test "failed storage reads cannot become writes", c do
    failing = {ReadAdapter, read: fn _ -> {:error, :offline} end}
    opts = [namespace: "read-fault"]
    assert {:error, :offline} = Persistence.load_agent(failing, Basic, c.agent.id, opts)
    assert {:error, :offline} = Persistence.save_agent(failing, c.agent, opts)
    assert {:error, :offline} = Persistence.delete_agent(failing, Basic, c.agent.id, opts)

    raising = {ReadAdapter, read: fn _ -> raise "read failed" end}

    assert {:error,
            %Jido.Error.ExecutionError{
              details: %{
                code: :persistence_callback_failed,
                operation: :delete,
                kind: :error,
                reason: %RuntimeError{message: "read failed"}
              }
            }} = Persistence.delete_agent(raising, Basic, c.agent.id, opts)

    invalid = {ReadAdapter, read: fn _ -> :invalid end}

    assert {:error,
            %Jido.Error.ExecutionError{
              details: %{
                code: :persistence_invalid_callback_result,
                operation: :get,
                result: :invalid
              }
            }} = Persistence.delete_agent(invalid, Basic, c.agent.id, opts)
  end

  @tag obligation: ["jido.persistence.I6", "jido.persistence.I9"]
  test "snapshot boundaries reject malformed values and context", c do
    {:ok, snapshot} = Persistence.snapshot(c.agent)

    for invalid <- [nil, [], %URI{}] do
      assert {:error, _} = Persistence.snapshot(c.agent, context: invalid)
      assert {:error, _} = Persistence.restore(snapshot, context: invalid)
      assert {:error, _} = Persistence.restore(invalid)
      assert {:error, _} = Checkpoint.default_restore(Basic, invalid, %{})
      assert {:error, _} = Checkpoint.default_checkpoint(invalid, %{})
    end

    assert {:error, _} = Persistence.restore(Map.put(snapshot, :unknown, true))
    assert Persistence.portable_term?(%{nested: [1, "two"]})
    refute Persistence.portable_term?(%{nested: self()})
  end

  @tag obligation: ["jido.persistence.I6", "jido.persistence.I11", "jido.persistence.I12"]
  test "snapshot and record callbacks receive only their bounded context", c do
    agent = ContextAgent.instantiate!(id: "context-agent")
    public_context = %{observer: self(), marker: :public}

    assert {:ok, direct} = Checkpoint.checkpoint(agent, public_context)
    assert_receive {:checkpoint_context, ^public_context}
    assert {:ok, ^agent} = Checkpoint.restore(ContextAgent, direct, public_context)
    assert_receive {:restore_context, ^public_context}

    assert {:error, %Jido.Agent.Error{code: :snapshot_identity, path: [:agent, :module]}} =
             Checkpoint.restore(Basic, direct, public_context)

    assert_receive {:restore_context, ^public_context}

    assert {:ok, default} = Checkpoint.default_checkpoint(agent, %{})
    assert default.state_format == :default
    assert {:ok, ^agent} = Checkpoint.default_restore(ContextAgent, default, %{})
    assert {:error, %Jido.Agent.Error{code: :invalid_snapshot}} = Checkpoint.checkpoint(agent, [])

    assert {:error, :checkpoint_rejected} =
             Checkpoint.checkpoint(agent, %{mode: :error})

    assert {:error,
            %Jido.Agent.Error{
              code: :invalid_snapshot_state,
              path: [:agent, :state],
              details: %{result: :invalid}
            }} =
             Checkpoint.checkpoint(agent, %{mode: :invalid})

    assert {:error, :restore_rejected} =
             Checkpoint.restore(ContextAgent, direct, %{mode: :error})

    assert {:error, %Jido.Agent.Error{code: :invalid_snapshot_state, path: [:agent, :state]}} =
             Checkpoint.restore(ContextAgent, direct, %{mode: :invalid})

    assert {:ok, snapshot} = Persistence.snapshot(agent, context: public_context)
    assert_receive {:checkpoint_context, ^public_context}
    assert {:ok, ^agent} = Persistence.restore(snapshot, context: public_context)
    assert_receive {:restore_context, ^public_context}

    instance = :"persistence_context_#{System.unique_integer([:positive])}"
    Process.register(self(), instance)

    opts = [
      namespace: "context-boundary",
      partition: "blue",
      revision: 2,
      reason: :contract,
      instance: instance
    ]

    assert :ok = Persistence.save_agent(c.store, agent, opts)

    assert_receive {:checkpoint_context,
                    %{
                      instance: ^instance,
                      partition: "blue",
                      revision: 2,
                      reason: :contract
                    }}

    assert {:ok, ^agent} =
             Persistence.load_agent(c.store, ContextAgent, agent.id,
               namespace: "context-boundary",
               partition: "blue",
               instance: instance
             )

    assert_receive {:restore_context,
                    %{
                      instance: ^instance,
                      partition: "blue",
                      revision: 2,
                      reason: :restore
                    }}
  end

  @tag obligation: "jido.persistence.I11"
  test "snapshot callbacks contain failures with stable diagnostic details" do
    agent = ContextAgent.instantiate!(id: "callback-failure")
    assert {:ok, checkpoint} = Checkpoint.checkpoint(agent)

    failures = [
      {:raise, :error, %RuntimeError{message: "checkpoint failed"}},
      {:throw, :throw, :checkpoint_failed},
      {:exit, :exit, :checkpoint_failed}
    ]

    for {mode, kind, reason} <- failures do
      assert {:error, %Jido.Error.ExecutionError{details: details}} =
               Checkpoint.checkpoint(agent, %{mode: mode})

      assert details == %{
               code: :agent_callback_failed,
               module: ContextAgent,
               callback: :checkpoint,
               kind: kind,
               reason: reason
             }
    end

    failures = [
      {:raise, :error, %RuntimeError{message: "restore failed"}},
      {:throw, :throw, :restore_failed},
      {:exit, :exit, :restore_failed}
    ]

    for {mode, kind, reason} <- failures do
      assert {:error, %Jido.Error.ExecutionError{details: details}} =
               Checkpoint.restore(ContextAgent, checkpoint, %{mode: mode})

      assert details == %{
               code: :agent_callback_failed,
               module: ContextAgent,
               callback: :restore,
               kind: kind,
               reason: reason
             }
    end
  end

  @tag obligation: ["jido.persistence.I6", "jido.persistence.I11"]
  test "custom snapshots reject malformed data and changed converted identity" do
    custom = Custom.instantiate!(id: "custom")
    {:ok, snapshot} = Persistence.snapshot(custom)

    assert {:error, %Jido.Agent.Error{code: :invalid_snapshot_state, path: [:agent, :state]}} =
             Persistence.restore(%{snapshot | agent: %{snapshot.agent | state: %{id: "other"}}})

    for changed <- [
          %{snapshot | agent: %{snapshot.agent | state: nil}},
          %{snapshot | agent: %{snapshot.agent | state: %URI{}}},
          %{snapshot | agent: %{snapshot.agent | vsn: -1}},
          Map.put(snapshot, :unknown, true)
        ] do
      assert {:error, _} = Persistence.restore(changed)
    end

    definition = Agent.define!(%{name: "embedded", vsn: 1})
    embedded = Agent.instantiate!(definition, id: "embedded")
    {:ok, saved} = Persistence.snapshot(embedded)
    changed = %{saved | agent: %{saved.agent | vsn: 2}}
    assert {:ok, %{vsn: 2}} = Persistence.restore(changed)
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

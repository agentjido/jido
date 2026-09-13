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
end

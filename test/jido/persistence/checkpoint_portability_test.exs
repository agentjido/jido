defmodule JidoTest.Persistence.CheckpointPortabilityTest do
  use JidoTest.Case, async: true
  @moduletag :research
  @moduletag capability: "PERSIST-02"

  alias Jido.Examples.CheckpointPortabilityProbe, as: Probe
  alias Jido.Examples.PersistenceProbeStore, as: Store
  alias Jido.Persistence

  setup do
    {:ok,
     store: {Store, store: start_supervised!(Store)}, id: unique_id("checkpoint-portability")}
  end

  test "nested portable values survive a save and load", c do
    agent =
      Probe.new!(
        id: c.id,
        state: %{payload: %{job: %{id: "job-1", attempts: [1, 2], result: {:ok, "done"}}}}
      )

    assert :ok = Persistence.save_agent(c.store, agent, revision: 3)
    assert {:ok, ^agent, 3} = Persistence.load_agent_with_revision(c.store, Probe, c.id)
  end

  test "Agent acceptance rejects a process handle before persistence", c do
    assert {:error,
            %Jido.Error.ValidationError{
              details: %{
                code: :non_portable_term,
                path: [:agent_state, :payload, :job, :worker]
              }
            }} = Probe.new(id: c.id, state: %{payload: %{job: %{worker: self()}}})

    key = Persistence.agent_key(nil, Probe, c.id)
    assert {:error, :not_found} = Store.get(key, elem(c.store, 1))
  end

  test "Agent acceptance rejects a nested improper list without raising", c do
    assert {:error,
            %Jido.Error.ValidationError{
              details: %{
                code: :non_portable_term,
                path: [:agent_state, :payload, :job, :values, 1]
              }
            }} = Probe.new(id: c.id, state: %{payload: %{job: %{values: [1 | self()]}}})

    key = Persistence.agent_key(nil, Probe, c.id)
    assert {:error, :not_found} = Store.get(key, elem(c.store, 1))
  end

  test "load rejects a nested process handle supplied by storage", c do
    assert :ok = Probe.store_payload(c.store, c.id, %{job: %{worker: self()}})

    assert {:error,
            %Jido.Error.ValidationError{
              details: %{
                code: :non_portable_term,
                path: [:record, :checkpoint, :state, :payload, :job, :worker]
              }
            }} = Persistence.load_agent(c.store, Probe, c.id)
  end
end

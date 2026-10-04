defmodule JidoTest.Persistence.CheckpointPortabilityTest do
  use JidoTest.Case, async: true
  @moduletag capability: "PERSIST-02"

  alias Jido.Persistence
  alias JidoTest.Persistence.CheckpointPortabilityProbe, as: Probe
  alias JidoTest.Persistence.ProbeStore, as: Store

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

    assert :ok =
             Persistence.save_agent(c.store, agent, namespace: "persistence-probe", revision: 3)

    assert {:ok, ^agent, 3} =
             Persistence.load_agent_with_revision(c.store, Probe, c.id,
               namespace: "persistence-probe"
             )
  end

  test "default persistence rejects a process handle accepted by live state", c do
    agent = Probe.new!(id: c.id, state: %{payload: %{job: %{worker: self()}}})

    assert {:error,
            %Jido.Error.ValidationError{
              details: %{
                code: :non_portable_term,
                path: [:checkpoint, :state, :payload, :job, :worker]
              }
            }} = Persistence.save_agent(c.store, agent, namespace: "persistence-probe")

    key = Persistence.agent_key(Jido.Agent.Ref.new!(namespace: "persistence-probe", id: c.id))
    assert {:error, :not_found} = Store.get(key, elem(c.store, 1))
  end

  test "default persistence rejects a nested improper list without raising", c do
    agent = Probe.new!(id: c.id, state: %{payload: %{job: %{values: [1 | self()]}}})

    assert {:error,
            %Jido.Error.ValidationError{
              details: %{
                code: :non_portable_term,
                path: [:checkpoint, :state, :payload, :job, :values, 1]
              }
            }} = Persistence.save_agent(c.store, agent, namespace: "persistence-probe")

    key = Persistence.agent_key(Jido.Agent.Ref.new!(namespace: "persistence-probe", id: c.id))
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
            }} = Persistence.load_agent(c.store, Probe, c.id, namespace: "persistence-probe")
  end

  test "load rejects every prohibited term class supplied by storage", c do
    port = Port.open({:spawn_executable, System.find_executable("true")}, [])
    on_exit(fn -> if Port.info(port), do: Port.close(port) end)

    values = [
      self(),
      port,
      make_ref(),
      fn -> :runtime end,
      [1 | :improper],
      <<1::size(1)>>
    ]

    for {value, index} <- Enum.with_index(values) do
      id = "#{c.id}-#{index}"
      assert :ok = Probe.store_payload(c.store, id, %{job: %{runtime: value}})

      assert {:error,
              %Jido.Error.ValidationError{
                details: %{
                  code: :non_portable_term,
                  path: path
                }
              }} = Persistence.load_agent(c.store, Probe, id, namespace: "persistence-probe")

      assert Enum.take(path, 6) == [:record, :checkpoint, :state, :payload, :job, :runtime]
      assert length(path) <= 20
    end
  end
end

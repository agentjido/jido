defmodule Jido.Persistence.IdentityTest do
  use ExUnit.Case, async: false

  alias Jido.Agent.Ref
  alias Jido.Persistence
  alias Jido.Persistence.{ETS, File}
  alias JidoTest.AgentFixtures.CounterAgent, as: Basic
  alias JidoTest.AgentRuntimeFixtures.RuntimeAgent

  defmodule BarrierAdapter do
    @behaviour Jido.Persistence.Adapter
    defdelegate get(key, opts), to: ETS

    def compare_and_swap(key, expected, value, opts) do
      send(Keyword.fetch!(opts, :observer), {:identity_cas, self(), key})

      receive do
        :write -> ETS.compare_and_swap(key, expected, value, opts)
      after
        5_000 -> {:error, {:rejected, :barrier_timeout}}
      end
    end
  end

  setup do
    table = :"identity_#{System.unique_integer([:positive])}"
    %{store: {ETS, table: table}, agent: Basic.new!(id: "counter")}
  end

  test "writers with different instance names share one CAS record", c do
    {ETS, opts} = c.store
    barrier = {BarrierAdapter, Keyword.put(opts, :observer, self())}
    ref = Ref.new!(namespace: "shared", id: c.agent.id)
    key = Persistence.agent_key(ref)

    writers =
      for instance <- [:first, :second] do
        Task.async(fn ->
          Persistence.create_agent(barrier, c.agent, instance: instance, namespace: ref.namespace)
        end)
      end

    assert_receive {:identity_cas, first, ^key}
    assert_receive {:identity_cas, second, ^key}
    send(first, :write)
    send(second, :write)
    assert Enum.sort(Enum.map(writers, &Task.await/1)) == [:ok, {:error, :conflict}]

    assert :ets.info(:"#{opts[:table]}_records", :size) == 1

    assert {:ok, restored} =
             Persistence.load_agent(c.store, Basic, c.agent.id, namespace: ref.namespace)

    assert restored == c.agent
  end

  test "the module cannot create a second durable identity", c do
    opts = [namespace: "shared"]
    assert :ok = Persistence.create_agent(c.store, c.agent, opts)
    other = RuntimeAgent.new!(id: c.agent.id)
    assert {:error, :conflict} = Persistence.create_agent(c.store, other, opts)

    assert {:error, {:invalid_persistence_record, :agent_module}} =
             Persistence.save_agent(c.store, other, opts ++ [revision: 1])

    assert {:error, {:invalid_persistence_record, :agent_module}} =
             Persistence.load_agent(c.store, RuntimeAgent, c.agent.id, opts)

    assert {:error, {:invalid_persistence_record, :agent_module}} =
             Persistence.delete_agent(c.store, RuntimeAgent, c.agent.id, opts)

    assert {:ok, restored} = Persistence.load_agent(c.store, Basic, c.agent.id, opts)
    assert restored == c.agent
  end

  test "namespaces and partitions keep distinct records", c do
    for {namespace, partition, count} <- [
          {"first", nil, 1},
          {"first", "blue", 2},
          {"second", nil, 3}
        ] do
      agent = %{c.agent | state: %{c.agent.state | count: count}}
      opts = [namespace: namespace, partition: partition]
      assert :ok = Persistence.create_agent(c.store, agent, opts)
      assert {:ok, ^agent} = Persistence.load_agent(c.store, Basic, agent.id, opts)
    end
  end

  test "a persistent activation requires a namespace", c do
    instance = :"unnamespaced_#{System.unique_integer([:positive])}"
    start_supervised!({Jido, name: instance})

    assert {:error, :stable_namespace_required} =
             Jido.start_agent(instance, Basic, id: c.agent.id, persistence: c.store)

    assert Jido.agent_count(instance) == 0
  end

  test "a File store keeps one record across instance names", c do
    path = Path.join(System.tmp_dir!(), "jido-identity-#{System.unique_integer([:positive])}")
    on_exit(fn -> Elixir.File.rm_rf!(path) end)
    store = {File, path: path}

    assert :ok =
             Persistence.create_agent(store, c.agent,
               instance: :first,
               namespace: "file-identity"
             )

    assert {:ok, restored} =
             Persistence.load_agent(store, Basic, c.agent.id,
               instance: :second,
               namespace: "file-identity"
             )

    assert restored == c.agent
    assert length(Path.wildcard(Path.join(path, "**/*.bin"))) == 1
  end
end

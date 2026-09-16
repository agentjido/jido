defmodule Jido.Persistence.MixedIdentityAuthorityTest do
  use ExUnit.Case, async: false

  alias Jido.Agent.Ref
  alias Jido.Persistence
  alias Jido.Persistence.{ETS, File, WriteAuthority}
  alias JidoTest.AgentFixtures.CounterAgent, as: Basic

  defmodule BarrierAdapter do
    @behaviour Jido.Persistence.Adapter

    @impl true
    defdelegate get(key, opts), to: ETS

    @impl true
    def compare_and_swap(key, expected, value, opts) do
      if key == Keyword.fetch!(opts, :gate_key) do
        send(Keyword.fetch!(opts, :observer), {:authority_cas, self(), key})

        receive do
          :write -> ETS.compare_and_swap(key, expected, value, opts)
        end
      else
        ETS.compare_and_swap(key, expected, value, opts)
      end
    end
  end

  test "one migration gate gives compatible and Ref writers one CAS record" do
    c = context("mixed")

    assert {:ok, %WriteAuthority{mode: :ref, key: ref_key} = authority} =
             Persistence.establish_write_authority(c.store, Basic, c.agent.id, c.ref_opts)

    assert ref_key == c.ref_key
    assert record_count(c.adapter_opts) == 0

    barrier =
      {BarrierAdapter, c.adapter_opts ++ [observer: self(), gate_key: ref_key]}

    ref_writer =
      Task.async(fn ->
        Persistence.create_agent(
          barrier,
          c.agent,
          Keyword.put(c.ref_opts, :write_authority, authority)
        )
      end)

    compatible_writer =
      Task.async(fn ->
        Persistence.create_agent(
          barrier,
          c.agent,
          Keyword.put(c.compatible_opts, :write_authority, authority)
        )
      end)

    assert_receive {:authority_cas, first, ^ref_key}, 1_000
    assert_receive {:authority_cas, second, ^ref_key}, 1_000
    send(first, :write)
    send(second, :write)

    assert Enum.sort([Task.await(ref_writer), Task.await(compatible_writer)]) == [
             :ok,
             {:error, :conflict}
           ]

    assert record_count(c.adapter_opts) == 1
    assert {:ok, _bytes} = ETS.get(c.ref_key, c.adapter_opts)
    assert {:error, :not_found} = ETS.get(c.legacy_key, c.adapter_opts)

    compatible_load = Keyword.put(c.compatible_opts, :write_authority, authority)
    assert Persistence.load_agent(c.store, Basic, c.agent.id, compatible_load) == {:ok, c.agent}
  end

  test "a gate selects one existing compatible record without adding a record" do
    c = context("legacy")
    assert :ok = Persistence.create_agent(c.store, c.agent, c.compatible_opts)
    assert record_count(c.adapter_opts) == 1

    assert {:ok, %WriteAuthority{mode: :legacy} = authority} =
             Persistence.establish_write_authority(c.store, Basic, c.agent.id, c.ref_opts)

    assert record_count(c.adapter_opts) == 1

    opts =
      c.ref_opts
      |> Keyword.put(:write_authority, authority)
      |> Keyword.put(:revision, 1)
      |> Keyword.put(:expected_revision, 0)

    assert :ok = Persistence.save_agent(c.store, c.agent, opts)
    assert record_count(c.adapter_opts) == 1
    assert {:ok, _bytes} = ETS.get(c.legacy_key, c.adapter_opts)
    assert {:error, :not_found} = ETS.get(c.ref_key, c.adapter_opts)
  end

  test "a File migration gate keeps one checkpoint file" do
    path = Path.join(System.tmp_dir!(), "jido-authority-#{System.unique_integer([:positive])}")
    on_exit(fn -> Elixir.File.rm_rf!(path) end)
    store = {File, path: path}
    id = "file-authority"
    agent = Basic.new!(id: id)
    opts = [instance: :file_authority, namespace: "file-authority"]

    assert {:ok, authority} = Persistence.establish_write_authority(store, Basic, id, opts)
    assert Path.wildcard(Path.join(path, "**/*.bin")) == []

    assert :ok =
             Persistence.create_agent(
               store,
               agent,
               Keyword.put(opts, :write_authority, authority)
             )

    assert length(Path.wildcard(Path.join(path, "**/*.bin"))) == 1
  end

  test "the migration gate rejects an existing identity collision" do
    c = context("collision")
    assert :ok = ETS.put(c.legacy_key, <<1>>, c.adapter_opts)
    assert :ok = ETS.put(c.ref_key, <<2>>, c.adapter_opts)

    assert {:error, {:persistence_identity_collision, _keys}} =
             Persistence.establish_write_authority(c.store, Basic, c.agent.id, c.ref_opts)

    assert record_count(c.adapter_opts) == 2
  end

  defp context(label) do
    suffix = System.unique_integer([:positive])
    id = "#{label}-#{suffix}"
    instance = :"mixed_identity_#{suffix}"
    namespace = "mixed-identity-#{suffix}"
    table = :"mixed_identity_table_#{suffix}"
    adapter_opts = [table: table]
    agent = Basic.new!(id: id)
    legacy_key = Persistence.agent_key(instance, Basic, id)
    ref_key = Persistence.agent_key(Ref.new!(namespace: namespace, id: id))
    assert {:error, :not_found} = ETS.get(legacy_key, adapter_opts)

    %{
      agent: agent,
      store: {ETS, adapter_opts},
      adapter_opts: adapter_opts,
      compatible_opts: [instance: instance],
      ref_opts: [instance: instance, namespace: namespace],
      legacy_key: legacy_key,
      ref_key: ref_key
    }
  end

  defp record_count(opts) do
    table = :"#{Keyword.fetch!(opts, :table)}_records"
    :ets.info(table, :size)
  end
end

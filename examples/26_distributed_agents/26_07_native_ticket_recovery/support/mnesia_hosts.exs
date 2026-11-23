defmodule Jido.Examples.DistributedAgents.MnesiaHosts do
  @moduledoc false

  import ExUnit.Assertions
  import Jido.Test.AgentServer.PeerCase, only: [peer_call: 4]

  def open(c, table) do
    for peer <- [c.peer_a, c.peer_b] do
      assert :stopped = peer_call(peer, :mnesia, :stop, [])
    end

    assert :ok = peer_call(c.peer_b, Application, :put_env, [:mnesia, :dir, String.to_charlist(c.tmp_dir)])
    assert :ok = peer_call(c.peer_b, :mnesia, :create_schema, [[c.node_b]])
    assert :ok = peer_call(c.peer_b, :mnesia, :start, [])

    assert {:atomic, :ok} =
             peer_call(c.peer_b, :mnesia, :create_table, [
               table,
               [attributes: [:key, :value], type: :set, disc_copies: [c.node_b]]
             ])

    join_client(c, table)
    {Jido.Persistence.Mnesia, table: table, sync_writes: true}
  end

  def join_client(c, table) do
    assert :ok = peer_call(c.peer_a, Application, :put_env, [:mnesia, :schema_location, :ram])
    assert :ok = peer_call(c.peer_a, :mnesia, :start, [])
    assert {:ok, [c.node_b]} == peer_call(c.peer_a, :mnesia, :change_config, [:extra_db_nodes, [c.node_b]])
    assert :ok = peer_call(c.peer_a, :mnesia, :wait_for_tables, [[table], 5_000])
    assert [c.node_b] == peer_call(c.peer_a, :mnesia, :table_info, [table, :disc_copies])
    assert [] == peer_call(c.peer_a, :mnesia, :table_info, [table, :ram_copies])
    assert c.node_b == peer_call(c.peer_a, :mnesia, :table_info, [table, :where_to_read])
    :ok
  end

  def saved_wakes(c, profile, namespace) do
    alias Jido.Persistence.Config

    assert {:ok, config} = peer_call(c.peer_b, Config, :open, [profile])
    prefix = "jido:wake:v3:" <> Base.url_encode64(namespace, padding: false)
    assert {:ok, %{buckets: buckets}} = read_wake_record(c.peer_b, profile, config, prefix <> ":index")

    for {bucket, shards} <- buckets,
        {shard, minimum_generation} <- shards,
        key = "#{prefix}:bucket:#{bucket}:shard:#{shard}",
        {:ok, %{entries: entries, generation: generation}} = read_wake_record(c.peer_b, profile, config, key),
        generation >= minimum_generation,
        entry <- entries,
        do: entry
  end

  defp read_wake_record(peer, {adapter, opts}, config, key) do
    assert {:ok, bytes} = peer_call(peer, adapter, :get, [key, opts])
    Jido.Persistence.Config.decode(config, bytes, trusted: true)
  end
end

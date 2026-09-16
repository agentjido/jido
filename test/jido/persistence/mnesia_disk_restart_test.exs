defmodule JidoTest.Persistence.MnesiaDiskRestartTest do
  use JidoTest.PeerCase, async: false

  alias Jido.Persistence.{Mnesia, Store}

  test "a disc copy retains committed bytes after Mnesia restarts", c do
    directory =
      Path.join(System.tmp_dir!(), "jido-mnesia-disk-#{System.unique_integer([:positive])}")

    File.mkdir_p!(directory)
    on_exit(fn -> File.rm_rf!(directory) end)

    assert :stopped = peer_call(c.peer_a, :mnesia, :stop, [])

    assert :ok =
             peer_call(c.peer_a, Application, :put_env, [
               :mnesia,
               :dir,
               String.to_charlist(directory)
             ])

    assert :ok = peer_call(c.peer_a, :mnesia, :create_schema, [[c.node_a]])
    assert {:ok, _started} = peer_call(c.peer_a, Application, :ensure_all_started, [:mnesia])

    table = :jido_mnesia_disk_restart_records

    assert {:atomic, :ok} =
             peer_call(c.peer_a, :mnesia, :create_table, [
               table,
               [attributes: [:key, :value], disc_copies: [c.node_a]]
             ])

    store = {Mnesia, table: table}
    assert {:ok, ^store} = peer_call(c.peer_a, Store, :open, [store])

    assert :ok =
             peer_call(c.peer_a, Store, :compare_and_swap, [
               store,
               "record",
               :not_found,
               <<0, 255>>
             ])

    assert :stopped = peer_call(c.peer_a, :mnesia, :stop, [])
    assert :ok = peer_call(c.peer_a, :mnesia, :start, [])
    assert :ok = peer_call(c.peer_a, :mnesia, :wait_for_tables, [[table], 5_000])
    assert {:ok, <<0, 255>>, <<0, 255>>} = peer_call(c.peer_a, Store, :read, [store, "record"])
    assert :stopped = peer_call(c.peer_a, :mnesia, :stop, [])
  end
end

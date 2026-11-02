defmodule JidoTest.Persistence.ETSOwnerTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureLog
  alias Jido.Persistence.ETS

  setup do
    base = :"ets_owner_test_#{System.unique_integer([:positive])}"
    table = :"#{base}_records"

    on_exit(fn ->
      if :ets.whereis(table) != :undefined, do: :ets.delete(table)
    end)

    {:ok, opts: [table: base], table: table, owner: Process.whereis(ETS.Owner)}
  end

  for reason <- [:normal, :killed] do
    @tag exit_reason: reason
    test "a #{reason} creator leaves usable data without a transfer error log", c do
      test = self()
      table = c.table
      owner = c.owner

      log =
        capture_log(fn ->
          :erlang.trace(owner, true, [:receive, {:tracer, self()}])

          {creator, monitor} =
            spawn_monitor(fn ->
              :ok = ETS.put("key", "saved", c.opts)
              send(test, {:created, self()})

              receive do
                :stop -> :ok
              end
            end)

          try do
            assert_receive {:created, ^creator}, 1_000
            assert :ets.info(table, :owner) == creator
            assert :ets.info(table, :heir) == owner

            if c.exit_reason == :normal,
              do: send(creator, :stop),
              else: Process.exit(creator, :kill)

            assert_receive {:DOWN, ^monitor, :process, ^creator, reason}, 1_000
            assert reason == c.exit_reason

            assert_receive {:trace, ^owner, :receive,
                            {:"ETS-TRANSFER", ^table, ^creator, {:jido_persistence_ets, ^table}}},
                           1_000

            # The system reply follows the transfer handler in the owner's mailbox.
            _ = :sys.get_state(owner)
            assert :ets.info(table, :owner) == owner
            assert {:ok, "saved"} = ETS.get("key", c.opts)
            assert :ok = ETS.compare_and_swap("key", "saved", "updated", c.opts)
            assert {:ok, "updated"} = ETS.get("key", c.opts)
          after
            Process.exit(creator, :kill)
            :erlang.trace(owner, false, [:all])
          end
        end)

      refute log =~ "ETS-TRANSFER"
    end
  end

  test "owner shutdown drops inherited tables and replacement accepts new tables", c do
    {creator, monitor} = spawn_monitor(fn -> :ok = ETS.put("key", "old", c.opts) end)
    assert_receive {:DOWN, ^monitor, :process, ^creator, :normal}, 1_000
    assert :ets.info(c.table, :owner) == c.owner
    monitor = Process.monitor(c.owner)

    on_exit(fn ->
      if Process.whereis(ETS.Owner) == nil,
        do: Supervisor.restart_child(Jido.Supervisor, ETS.Owner)
    end)

    assert :ok = Supervisor.terminate_child(Jido.Supervisor, ETS.Owner)
    assert_receive {:DOWN, ^monitor, :process, _, :shutdown}, 1_000
    assert :ets.whereis(c.table) == :undefined
    assert {:ok, replacement} = Supervisor.restart_child(Jido.Supervisor, ETS.Owner)
    assert replacement != c.owner
    assert {:error, :not_found} = ETS.get("key", c.opts)
    assert :ets.info(c.table, :heir) == replacement
    assert :ok = ETS.put("key", "new", c.opts)
    assert {:ok, "new"} = ETS.get("key", c.opts)
  end
end

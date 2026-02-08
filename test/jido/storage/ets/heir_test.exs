defmodule JidoTest.Storage.ETS.HeirTest do
  use ExUnit.Case, async: true

  import JidoTest.Eventually

  alias Jido.Storage.ETS.Heir

  test "records ETS transfer events" do
    heir_pid = Process.whereis(Heir)
    assert is_pid(heir_pid)

    marker = {:heir_test_marker, make_ref()}
    send(heir_pid, {:"ETS-TRANSFER", :heir_test_table, self(), marker})

    event =
      eventually(fn ->
        Enum.find(Heir.transfers(), fn transfer ->
          transfer.table == :heir_test_table and
            transfer.from == self() and
            transfer.data == marker
        end)
      end)

    assert event.table == :heir_test_table
    assert event.from == self()
    assert event.data == marker
    assert is_integer(event.transferred_at)
  end

  test "ignores non-transfer messages" do
    heir_pid = Process.whereis(Heir)
    assert is_pid(heir_pid)

    marker = {:heir_unknown_message, make_ref()}
    send(heir_pid, marker)

    refute_eventually(
      Enum.any?(Heir.transfers(), fn transfer -> transfer.data == marker end),
      timeout: 50
    )
  end
end

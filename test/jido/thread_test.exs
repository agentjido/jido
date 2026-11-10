defmodule Jido.ThreadTest do
  use ExUnit.Case, async: true

  alias Jido.Thread
  alias Jido.Thread.Entry

  test "stores feature-neutral Agent interactions in append order" do
    thread =
      Thread.new(id: "agent-thread", now: 10, metadata: %{channel: "orders"})
      |> Thread.append([
        %{id: "command", at: 11, kind: :command, payload: %{name: "reserve"}},
        %{id: "result", at: 12, kind: :result, refs: %{command: "command"}}
      ])

    assert thread.rev == 2
    assert Thread.entry_count(thread) == 2

    assert Enum.map(Thread.to_list(thread), &{&1.seq, &1.kind}) == [
             {0, :command},
             {1, :result}
           ]

    assert Thread.last(thread).id == "result"
    assert Thread.get_entry(thread, 0).id == "command"
    assert Enum.map(Thread.filter_by_kind(thread, [:result]), & &1.id) == ["result"]
    assert Enum.map(Thread.slice(thread, 0, 0), & &1.id) == ["command"]
  end

  test "round-trips portable Thread and Entry values without feature modules" do
    entry =
      Entry.new(
        id: "event",
        seq: 9,
        at: 11,
        kind: "domain.event",
        payload: %{"value" => 3},
        refs: %{"cause" => "command"}
      )

    thread = Thread.new(id: "portable-thread", now: 10) |> Thread.append(entry)

    assert {:ok, ^entry} = entry |> Entry.encode() |> Entry.decode()
    assert {:ok, ^thread} = thread |> Thread.encode() |> Thread.decode()
    assert Runic.Identity.Projectable.identity_document(thread) == Thread.encode(thread)
  end

  test "rejects process-local data at the Thread value boundary" do
    assert_raise ArgumentError, "invalid thread entry", fn ->
      Entry.new(kind: :command, payload: %{caller: self()})
    end

    assert_raise ArgumentError, "invalid thread", fn ->
      Thread.new(id: "invalid-thread", now: 1, metadata: %{caller: self()})
    end
  end
end

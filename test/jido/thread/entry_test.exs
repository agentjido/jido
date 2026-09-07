defmodule Jido.Thread.EntryTest do
  use ExUnit.Case, async: true

  alias Jido.Thread.Entry

  test "creates an Entry with defaults" do
    entry = Entry.new(%{})

    assert entry.seq == 0
    assert entry.kind == :note
    assert entry.payload == %{}
    assert entry.refs == %{}
    assert is_integer(entry.at)
  end

  test "accepts keyword, atom-key, and string-key attributes" do
    assert %Entry{kind: :message, payload: %{role: "user"}} =
             Entry.new(kind: :message, payload: %{role: "user"})

    now = System.system_time(:millisecond)

    assert %Entry{
             id: "entry_123",
             seq: 5,
             at: ^now,
             kind: :tool_call,
             payload: %{name: "search"},
             refs: %{signal_id: "sig_1"}
           } =
             Entry.new(%{
               id: "entry_123",
               seq: 5,
               at: now,
               kind: :tool_call,
               payload: %{name: "search"},
               refs: %{signal_id: "sig_1"}
             })

    assert %Entry{kind: :error, payload: %{"msg" => "failed"}} =
             Entry.new(%{"kind" => :error, "payload" => %{"msg" => "failed"}})
  end

  test "atom keys take precedence and false values are not replaced" do
    entry = Entry.new(%{:payload => false, "payload" => %{from: :string}})
    assert entry.payload == false
  end

  test "invalid constructor input fails at the public boundary" do
    for value <- [nil, :invalid, 42, "entry"] do
      assert_raise FunctionClauseError, fn -> Entry.new(value) end
    end
  end
end

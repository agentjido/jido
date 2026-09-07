defmodule Jido.Thread.EntryTest do
  use ExUnit.Case, async: true

  alias Jido.Thread.Entry

  defmodule EntryLookalike do
    @moduledoc false
    defstruct [:id, :seq, :at, :kind, :payload, :refs]
  end

  test "schema accepts Entry values and rejects lookalikes and malformed fields" do
    entry = Entry.new(id: "entry-1", seq: 1, at: 1_000, kind: :message)
    assert {:ok, ^entry} = Zoi.parse(Entry.schema(), entry)
    assert {:ok, ^entry} = Zoi.parse(Entry.schema(), Map.from_struct(entry))

    lookalike = struct(EntryLookalike, entry |> Map.from_struct() |> Map.to_list())

    for malformed <- [
          lookalike,
          %{entry | id: ""},
          %{entry | seq: -1},
          %{entry | at: "now"},
          %{entry | kind: "message"},
          %{entry | payload: %URI{host: "example.com"}},
          %{entry | refs: %URI{host: "example.com"}}
        ] do
      assert {:error, _errors} = Zoi.parse(Entry.schema(), malformed)
    end
  end

  test "creates an Entry with defaults" do
    entry = Entry.new(%{})

    assert String.starts_with?(entry.id, "entry_")
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

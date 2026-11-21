Code.require_file("thread_agent.ex", __DIR__)

defmodule Jido.Examples.Conversation.ThreadValueTest do
  use ExUnit.Case, async: true

  @moduletag :integration

  alias Jido.Examples.Conversation.ThreadValue
  alias Jido.Thread

  test "a Thread is an immutable append-only portable value" do
    thread = ThreadValue.build()

    assert thread.rev == 2
    assert Thread.entry_count(thread) == 2
    assert Thread.last(thread).kind == :note
    assert [%{payload: %{"case_id" => "case-7"}}] = Thread.filter_by_kind(thread, :case_opened)
    assert Enum.map(Thread.slice(thread, 0, 1), & &1.seq) == [0, 1]

    assert {:ok, decoded} = thread |> Thread.encode() |> JSON.encode!() |> JSON.decode!() |> Thread.decode()
    assert decoded == thread
  end

  test "appending returns a new value and leaves the source unchanged" do
    source = Thread.new(id: "empty-thread", now: 100)
    next = Thread.append(source, %{kind: :note, at: 101, payload: %{"text" => "one"}})

    assert source.rev == 0
    assert source.entries == []
    assert next.rev == 1
  end
end

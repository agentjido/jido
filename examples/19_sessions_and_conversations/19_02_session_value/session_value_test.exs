Code.require_file("session_value.ex", __DIR__)

defmodule Jido.Examples.AI.SessionValueTest do
  use ExUnit.Case, async: true

  @moduletag :integration

  alias Jido.Examples.AI.SessionValue

  test "an immutable Session records and projects one complete exchange" do
    session = SessionValue.new(id: "example-session", now: 100)
    assert {:ok, recorded} = SessionValue.record(session, "portable note", 101)
    assert session.rev == 0
    assert recorded.rev == 2

    assert {:ok, messages} = SessionValue.messages(recorded)

    assert Enum.map(messages, &{&1.role, &1.content}) == [
             {:user, "portable note"},
             {:assistant, "Recorded: portable note"}
           ]
  end

  test "Session JSON data round-trips and a closed value rejects append" do
    assert {:ok, recorded} = SessionValue.new(id: "json-session", now: 10) |> SessionValue.record("one", 11)

    assert {:ok, decoded} =
             recorded |> Jido.Session.encode() |> JSON.encode!() |> JSON.decode!() |> Jido.Session.decode()

    assert decoded == recorded

    closed = SessionValue.close(decoded)
    assert closed.status == :closed
    assert {:error, :invalid_context} = SessionValue.record(closed, "two", 20)
  end
end

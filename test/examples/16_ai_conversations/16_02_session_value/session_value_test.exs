Code.require_file("../../support/loader.exs", __DIR__)

JidoTest.Examples.Loader.require_source!("16_ai_conversations/16_02_session_value/session_value.ex")

defmodule JidoTest.Examples.AI.SessionValueTest do
  use JidoTest.Case, async: true

  @moduletag :example

  setup_all do
    JidoTest.Examples.Loader.require_source!("16_ai_conversations/16_02_session_value/session_value.ex")
    :ok
  end

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

Code.require_file("non_ai_session.ex", __DIR__)

defmodule Jido.Examples.Conversation.SupportCaseTest do
  use ExUnit.Case, async: true

  @moduletag :integration

  alias Jido.Examples.Conversation.SupportCase

  test "a Session can own non-AI application history" do
    source = SupportCase.new("case-7")

    recorded =
      source
      |> SupportCase.record(:case_opened, %{"priority" => "high"})
      |> SupportCase.record(:owner_assigned, %{"team" => "payments"})

    assert source.rev == 0
    assert recorded.metadata["case_id"] == "case-7"

    assert SupportCase.events(recorded) == [
             %{sequence: 0, type: "case_opened", data: %{"priority" => "high"}},
             %{sequence: 1, type: "owner_assigned", data: %{"team" => "payments"}}
           ]

    assert {:ok, decoded} = recorded |> Jido.Session.encode() |> Jido.Session.decode()
    assert decoded == recorded
  end
end

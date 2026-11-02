defmodule Jido.AI.Contract.ConversationTest do
  use Covenant.Case, component: "jido_ai.conversation", async: true

  alias Jido.AI.Thread.Projection
  alias Jido.{Session, Thread}

  @tag obligation: ["jido_ai.conversation.I2", "jido_ai.conversation.I3"]
  test "projection reports the exact reason for each message decision" do
    session = Session.new(id: "contract-decisions", now: 1)
    session = append!(session, %{role: :user, content: "Failed"}, 2, %{run_id: "failed"})

    session =
      Projection.observe(
        session,
        :ai_request_outcome,
        %{status: :failed},
        %{run_id: "failed"},
        3
      )

    session = append!(session, %{role: :user, content: "Old"}, 4)

    session =
      append!(
        session,
        %{
          role: :assistant,
          content: "",
          tool_calls: [%{id: "open", name: "lookup", arguments: %{id: 1}}]
        },
        5
      )

    session = append!(session, %{role: :user, content: "Current"}, 6)

    assert {:ok, explanation} = Projection.explain(session, %{max_messages: 1})
    [failed, old, open, current] = explanation.decisions

    assert Map.drop(failed, [:entry_id]) == %{
             seq: 0,
             state: :excluded,
             reason: :request_not_completed,
             refs: %{run_id: "failed"}
           }

    assert Map.drop(old, [:entry_id]) == %{
             seq: 2,
             state: :excluded,
             reason: :outside_context_window,
             refs: %{}
           }

    assert Map.drop(open, [:entry_id]) == %{
             seq: 3,
             state: :excluded,
             reason: :incomplete_tool_exchange,
             refs: %{}
           }

    assert Map.drop(current, [:entry_id]) == %{
             seq: 4,
             state: :included,
             reason: :projected,
             refs: %{}
           }

    assert explanation.available_messages == 2
    assert explanation.included_messages == 1
    assert explanation.dropped_messages == 1
    assert explanation.first_seq == 4
    assert explanation.last_seq == 4
    assert Enum.map(explanation.messages, &{&1.role, &1.content}) == [{:user, "Current"}]

    assert {:ok, projection} = Projection.project(session, %{max_messages: 1})
    refute Map.has_key?(projection, :entries)
    refute Map.has_key?(projection, :decisions)
    assert projection.included_messages == 1

    assert {:ok, messages} = Projection.messages(session)

    assert Enum.map(messages, &{&1.role, &1.content}) == [
             {:user, "Old"},
             {:user, "Current"}
           ]
  end

  @tag obligation: ["jido_ai.conversation.I2", "jido_ai.conversation.I5"]
  test "projection restores rich content, reasoning, and thread source metadata" do
    session = Session.new(id: "contract-rich-context", now: 1)

    user =
      ReqLLM.Context.user([
        ReqLLM.Message.ContentPart.text("Inspect this image."),
        ReqLLM.Message.ContentPart.image_url("https://example.com/image.png")
      ])

    assistant = %ReqLLM.Message{
      ReqLLM.Context.assistant("Done")
      | reasoning_details: [
          %ReqLLM.Message.ReasoningDetails{
            text: "Short reasoning",
            signature: "opaque",
            provider: :openai,
            format: "contract",
            index: 0
          }
        ]
    }

    session = append_req!(session, user, 2, %{run_id: "rich"})
    session = append_req!(session, assistant, 3, %{run_id: "rich"})

    assert {:ok, projection} = Projection.context(session)
    [restored_user, restored_assistant] = ReqLLM.Context.to_list(projection.context)

    assert Enum.map(restored_user.content, &{&1.type, &1.text, &1.url}) == [
             {:text, "Inspect this image.", nil},
             {:image_url, nil, "https://example.com/image.png"}
           ]

    [reasoning] = restored_assistant.reasoning_details
    assert field(reasoning, :text) == "Short reasoning"
    assert field(reasoning, :signature) == "opaque"
    assert field(reasoning, :provider) == "openai"
    assert field(reasoning, :format) == "contract"
    assert field(reasoning, :index) == 0

    assert restored_user.metadata.jido.source == %{
             type: :thread_entry,
             entry_id: Enum.at(session.thread.entries, 0).id,
             seq: 0,
             at: 2,
             refs: %{run_id: "rich"}
           }

    assert restored_assistant.metadata.jido.source.seq == 1
  end

  @tag obligation: ["jido_ai.conversation.I2", "jido_ai.conversation.I5"]
  test "projection completes multi-call exchanges and preserves tool-call metadata" do
    session = Session.new(id: "contract-tool-exchange", now: 1)

    first =
      "call-1"
      |> ReqLLM.ToolCall.new("lookup", Jason.encode!(%{id: "42"}))
      |> ReqLLM.ToolCall.put_metadata(%{provider_native: :openai, trace_id: "trace-1"})

    second = ReqLLM.ToolCall.new("call-2", "search", Jason.encode!(%{query: "jido"}))
    assistant = ReqLLM.Context.assistant("", tool_calls: [first, second])

    session = append_req!(session, assistant, 2)
    session = append_req!(session, ReqLLM.Context.tool_result("call-1", "lookup", %{ok: true}), 3)

    assert {:ok, %{messages: []}} = Projection.project(session, %{})
    assert Projection.breakpoint(session) == nil

    session =
      append_req!(session, ReqLLM.Context.tool_result("call-2", "search", %{found: 1}), 4)

    assert Projection.breakpoint(session) == 2
    assert {:ok, projection} = Projection.context(session)
    [restored_assistant, first_result, second_result] = ReqLLM.Context.to_list(projection.context)
    [restored_first, restored_second] = restored_assistant.tool_calls

    assert ReqLLM.ToolCall.to_map(restored_first) == %{
             id: "call-1",
             name: "lookup",
             arguments: %{"id" => "42"},
             metadata: %{
               "provider_native" => "openai",
               "trace_id" => "trace-1"
             }
           }

    assert ReqLLM.ToolCall.metadata(restored_first) == %{
             "provider_native" => "openai",
             "trace_id" => "trace-1"
           }

    assert ReqLLM.ToolCall.to_map(restored_second) == %{
             id: "call-2",
             name: "search",
             arguments: %{"query" => "jido"}
           }

    assert first_result.tool_call_id == "call-1"
    assert second_result.tool_call_id == "call-2"
  end

  @tag obligation: ["jido_ai.conversation.I2", "jido_ai.conversation.I4"]
  test "projection keeps a complete latest turn when a limit is smaller than that turn" do
    session = Session.new(id: "contract-window", now: 1)
    session = append!(session, %{role: :user, content: "Old question"}, 2)
    session = append!(session, %{role: :assistant, content: "Old answer"}, 3)
    session = append!(session, %{role: :user, content: "New question"}, 4)
    session = append!(session, %{role: :assistant, content: "New answer"}, 5)

    assert {:ok, projection} = Projection.project(session, %{max_messages: 1})

    assert Enum.map(projection.messages, &{&1.role, &1.content}) == [
             {:user, "New question"},
             {:assistant, "New answer"}
           ]

    assert projection.available_messages == 4
    assert projection.included_messages == 2
    assert projection.dropped_messages == 2
    assert projection.first_seq == 2
    assert projection.last_seq == 3

    assert {:ok, unlimited} = Projection.project(session, %{max_messages: 0, max_bytes: -1})
    assert unlimited.included_messages == 4
  end

  @tag obligation: "jido_ai.conversation.I1"
  test "Session and Thread revisions survive versioned encoding" do
    session = Session.new(id: "contract-session", now: 1)

    session =
      Session.append(session, [
        %{kind: :note, payload: %{"value" => 1}, at: 2},
        %{kind: :note, payload: %{"value" => 2}, at: 3}
      ])

    assert session.rev == 2
    assert session.thread.rev == 2
    assert Enum.map(session.thread.entries, & &1.seq) == [0, 1]
    assert {:ok, ^session} = session |> Session.encode() |> Session.decode()

    thread = session.thread
    assert {:ok, ^thread} = thread |> Thread.encode() |> Thread.decode()
  end

  @tag obligation: [
         "jido_ai.conversation.I2",
         "jido_ai.conversation.I3",
         "jido_ai.conversation.I4"
       ]
  test "projection keeps recent complete exchanges and excludes observations" do
    session = Session.new(id: "contract-projection", now: 1)

    session = append!(session, %{role: :user, content: "Old question"}, 2)
    session = append!(session, %{role: :assistant, content: "Old answer"}, 3)

    session =
      Projection.observe(
        session,
        :ai_model_attempt,
        %{version: 1, status: :ok},
        %{request_id: "request-1"},
        4
      )

    session = append!(session, %{role: :user, content: "Incomplete"}, 5)

    session =
      append!(
        session,
        %{
          role: :assistant,
          content: "",
          tool_calls: [%{id: "open", name: "lookup", arguments: %{}}]
        },
        6
      )

    session = append!(session, %{role: :user, content: "Current question"}, 7)
    session = append!(session, %{role: :assistant, content: "Current answer"}, 8)

    assert {:ok, projection} =
             Projection.project(session, %{max_messages: 2, max_bytes: 10_000})

    assert Enum.map(projection.messages, &{&1.role, text(&1)}) == [
             {:user, "Current question"},
             {:assistant, "Current answer"}
           ]

    assert [_attempt] = Thread.filter_by_kind(session.thread, :ai_model_attempt)
  end

  @tag obligation: "jido_ai.conversation.I5"
  test "tool content parts and metadata survive context restoration" do
    session = Session.new(id: "contract-content-parts", now: 1)

    session =
      append!(
        session,
        %{
          role: :assistant,
          content: "",
          tool_calls: [%{id: "image-1", name: "image_result", arguments: %{}}]
        },
        2
      )

    session =
      append!(
        session,
        %{
          role: :tool,
          tool_call_id: "image-1",
          name: "image_result",
          content: [
            ReqLLM.Message.ContentPart.text("Chart ready"),
            ReqLLM.Message.ContentPart.image_url("https://example.com/chart.png")
          ],
          output: %{asset_id: "asset-1"},
          metadata: %{tool_result_metadata: %{source: "contract"}}
        },
        3
      )

    assert {:ok, %{context: context}} = Projection.context(session)
    [_assistant, tool] = ReqLLM.Context.to_list(context)
    assert Enum.map(tool.content, & &1.type) == [:text, :image_url]
    assert tool.metadata.tool_output == %{"asset_id" => "asset-1"}
    assert tool.metadata["source"] == "contract"
  end

  defp append!(session, message, at, refs \\ %{}) do
    {:ok, session} = Projection.append(session, message, refs, at)
    session
  end

  defp append_req!(session, message, at, refs \\ %{}), do: append!(session, message, at, refs)

  defp text(message) do
    case message.content do
      content when is_binary(content) -> content
      content -> content |> Enum.filter(&(&1.type == :text)) |> Enum.map_join(& &1.text)
    end
  end

  defp field(map, key), do: Map.get(map, key, Map.get(map, Atom.to_string(key)))
end

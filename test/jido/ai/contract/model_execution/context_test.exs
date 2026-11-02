defmodule Jido.AI.ContextTest do
  use Covenant.Case, component: "jido_ai.model_execution", async: true

  @moduletag obligation: ["jido_ai.model_execution.I4", "jido_ai.model_execution.I5"]

  alias Jido.AI.Context
  alias Jido.AI.Thread.Projection

  test "wraps an existing ReqLLM context without thread or reasoning dependencies" do
    req_llm_context =
      ReqLLM.Context.new([
        ReqLLM.Context.system("Answer briefly."),
        ReqLLM.Context.user("Current request")
      ])

    assert {:ok, context} =
             Context.new(req_llm_context,
               metadata: %{
                 source: %{thread_id: "thread-1"},
                 call: %{request_id: "request-1"}
               }
             )

    assert context.stage == :open
    assert context.request.context == req_llm_context
    assert context.request.model == nil
    assert context.request.options == []
    assert context.metadata.source.thread_id == "thread-1"
  end

  test "applies a generic transformation once and sends the exact ReqLLM request" do
    req_llm_context = ReqLLM.Context.new([ReqLLM.Context.user("Use what you know.")])
    assert {:ok, context} = Context.new(req_llm_context)

    transform = fn req_context ->
      message =
        ReqLLM.Context.system("The customer name is Ada.",
          metadata: %{plugin: "customer-memory", record_id: "customer-name"}
        )

      %{req_context | messages: [message | req_context.messages]}
    end

    assert {:ok, transformed} = Context.transform(context, "plugin:customer-memory:1", transform)

    assert {:ok, ^transformed} =
             Context.transform(transformed, "plugin:customer-memory:1", fn _context ->
               raise "must not run twice"
             end)

    before = Context.snapshot(transformed, content: :none)

    assert {:ok, prepared} =
             Context.prepare(transformed,
               model: "openai:gpt-4o-mini",
               options: [temperature: 0]
             )

    assert prepared.stage == :prepared
    assert prepared.request.context == transformed.request.context
    assert prepared.request.model == "openai:gpt-4o-mini"
    assert prepared.request.options == [temperature: 0]
    assert is_binary(prepared.digest)
    assert {:error, :context_not_open} = Context.transform(prepared, "late", & &1)

    assert Enum.map(prepared.request.context.messages, &message_text/1) == [
             "The customer name is Ada.",
             "Use what you know."
           ]

    change = Context.diff(before, Context.snapshot(prepared, content: :none))
    assert change.before.stage == :open
    assert change.after.stage == :prepared
    assert change.request_changed
    refute change.messages_changed
  end

  test "snapshots expose ReqLLM shape, safe options, response context, and call metadata" do
    request_context =
      ReqLLM.Context.new([
        ReqLLM.Context.system("System text"),
        ReqLLM.Context.user("Secret input")
      ])

    assert {:ok, context} = Context.new(request_context, metadata: %{owner: "test"})

    assert {:ok, context} =
             Context.prepare(context,
               model: "openai:gpt-4o-mini",
               options: [max_tokens: 100, api_key: "do-not-record"]
             )

    assistant = ReqLLM.Context.assistant("Secret answer")

    response = %ReqLLM.Response{
      id: "response-1",
      model: "openai:gpt-4o-mini",
      context: ReqLLM.Context.append(request_context, assistant),
      message: assistant,
      finish_reason: :stop,
      usage: %{input_tokens: 12, output_tokens: 4, cache_read_tokens: 8},
      provider_meta: %{request_id: "req-1"}
    }

    assert {:ok, completed} = Context.complete(context, {:ok, response})

    manifest = completed |> Context.snapshot(content: :none) |> Context.Snapshot.to_map()
    assert manifest.stage == :completed
    assert manifest.shape.message_count == 2
    assert manifest.shape.tool_count == 0
    assert manifest.request.options[:api_key] == "[REDACTED]"
    assert manifest.response.status == :ok
    assert manifest.response.call_metadata.usage.input_tokens == 12
    assert length(manifest.response.context.messages) == 3
    refute Map.has_key?(hd(manifest.request.context.messages), :content)

    full = completed |> Context.snapshot(content: :full) |> Context.Snapshot.to_map()

    assert Enum.any?(full.request.context.messages, fn message ->
             Enum.any?(message.content, &(Map.get(&1, :text) == "Secret input"))
           end)

    encoded = completed |> Context.snapshot(content: :none) |> Context.Snapshot.encode()
    assert Context.Snapshot.decode!(encoded)["stage"] == "completed"
  end

  test "snapshots hash tool schemas and expose full schemas on request" do
    {:ok, tool} =
      ReqLLM.Tool.new(
        name: "lookup",
        description: "Look up one record",
        parameter_schema: %{
          "type" => "object",
          "properties" => %{"id" => %{"type" => "string"}},
          "required" => ["id"]
        },
        callback: fn _arguments -> {:error, :not_executable_here} end,
        strict: true
      )

    req_llm_context = %ReqLLM.Context{messages: [], tools: [tool]}
    assert {:ok, context} = Context.new(req_llm_context)

    assert {:ok, context} =
             Context.prepare(context, model: "openai:gpt-4o-mini", options: [])

    manifest = context |> Context.snapshot(content: :none) |> Context.Snapshot.to_map()
    [manifest_tool] = manifest.request.context.tools
    assert manifest_tool.name == "lookup"
    assert is_binary(manifest_tool.schema_digest)
    refute Map.has_key?(manifest_tool, :schema)

    full = context |> Context.snapshot(content: :full) |> Context.Snapshot.to_map()
    [full_tool] = full.request.context.tools
    assert full_tool.schema["function"]["parameters"]["required"] == ["id"]
  end

  test "projection explains exclusions and returns a canonical ReqLLM context" do
    session = Jido.Session.new(id: "session:context-decisions", now: 1)
    {:ok, session} = Projection.append(session, %{role: :user, content: "Old"}, %{run_id: "old"}, 2)

    session =
      Projection.observe(
        session,
        :ai_request_outcome,
        %{status: :failed},
        %{run_id: "old"},
        3
      )

    {:ok, session} = Projection.append(session, %{role: :user, content: "First"}, %{}, 4)

    {:ok, session} =
      Projection.append(
        session,
        %{
          role: :assistant,
          content: "",
          tool_calls: [%{id: "open", name: "lookup", arguments: %{}}]
        },
        %{},
        5
      )

    {:ok, session} = Projection.append(session, %{role: :user, content: "Current"}, %{}, 6)

    assert {:ok, projection} = Projection.context(session, %{max_messages: 1})
    assert [%ReqLLM.Message{role: :user} = message] = projection.context.messages
    assert message_text(message) == "Current"

    assert Enum.map(projection.decisions, & &1.reason) == [
             :request_not_completed,
             :outside_context_window,
             :incomplete_tool_exchange,
             :projected
           ]
  end

  test "thread projection restores rich content and reasoning details" do
    session = Jido.Session.new(id: "session:rich-context", now: 1)

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
            format: "test",
            index: 0
          }
        ]
    }

    assert {:ok, session} = Projection.append(session, user, %{}, 2)
    assert {:ok, session} = Projection.append(session, assistant, %{}, 3)
    assert {:ok, projection} = Projection.context(session)

    [restored_user, restored_assistant] = projection.context.messages

    assert Enum.map(restored_user.content, &{&1.type, &1.text, &1.url}) == [
             {:text, "Inspect this image.", nil},
             {:image_url, nil, "https://example.com/image.png"}
           ]

    [reasoning] = restored_assistant.reasoning_details
    assert field(reasoning, :text) == "Short reasoning"
    assert field(reasoning, :signature) == "opaque"
  end

  test "thread projection preserves ReqLLM tool-call metadata" do
    session = Jido.Session.new(id: "session:tool-call-metadata", now: 1)

    tool_call =
      "call-1"
      |> ReqLLM.ToolCall.new("lookup", Jason.encode!(%{id: "42"}))
      |> ReqLLM.ToolCall.put_metadata(%{provider_native: :openai, trace_id: "trace-1"})

    assistant = ReqLLM.Context.assistant("", tool_calls: [tool_call])
    tool_result = ReqLLM.Context.tool_result("call-1", "lookup", %{ok: true})

    assert {:ok, session} = Projection.append(session, assistant, %{}, 2)
    assert {:ok, session} = Projection.append(session, tool_result, %{}, 3)
    assert {:ok, projection} = Projection.context(session)

    [restored_assistant, _tool_result] = projection.context.messages
    [restored_call] = restored_assistant.tool_calls
    metadata = ReqLLM.ToolCall.metadata(restored_call)

    assert field(metadata, :provider_native) == "openai"
    assert field(metadata, :trace_id) == "trace-1"
  end

  defp message_text(message) do
    message.content
    |> Enum.filter(&(&1.type == :text))
    |> Enum.map_join(& &1.text)
  end

  defp field(map, key), do: Map.get(map, key, Map.get(map, Atom.to_string(key)))
end

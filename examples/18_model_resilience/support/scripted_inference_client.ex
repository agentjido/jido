Code.require_file("../../support/offline_inference_client.ex", __DIR__)

defmodule Jido.Examples.ModelResilience.ScriptedInferenceClient do
  @moduledoc "Deterministic model outcomes selected by an offline model name."

  @behaviour Jido.AI.InferenceClient

  alias Jido.Examples.Support.OfflineInferenceClient, as: Offline

  @impl true
  def generate_text("offline:primary-outage", _context, _options) do
    {:error,
     ReqLLM.Error.API.Request.exception(
       reason: "offline rate limit",
       status: 429,
       request_body: %{credential: "must-not-be-recorded"}
     )}
  end

  def generate_text("offline:invalid-credentials", _context, _options) do
    {:error,
     ReqLLM.Error.API.Request.exception(
       reason: "offline authorization failure",
       status: 401,
       request_body: %{credential: "must-not-be-recorded"}
     )}
  end

  def generate_text("offline:truncated", context, _options) do
    if repair_request?(context) do
      {:ok, response("offline:truncated", context, "Complete repaired answer", :stop)}
    else
      {:ok, response("offline:truncated", context, "Partial answer", :length)}
    end
  end

  def generate_text("offline:long-output", context, _options) do
    text = if repair_request?(context), do: "Short", else: String.duplicate("x", 11)
    {:ok, response("offline:long-output", context, text, :stop)}
  end

  def generate_text("offline:tool-error", context, _options) do
    if Enum.any?(ReqLLM.Context.to_list(context), &(&1.role == :tool)) do
      {:ok, response("offline:tool-error", context, "The inventory tool is unavailable.", :stop)}
    else
      call = ReqLLM.ToolCall.new("inventory-1", "resilience_failure_tool", ~s({"item":"part-7"}))
      {:ok, tool_response("offline:tool-error", context, call)}
    end
  end

  def generate_text(model, context, _options) do
    {:ok, response(model, context, "Offline answer from #{model}", :stop)}
  end

  @impl true
  def stream_text("offline:partial-stream" = model, context, _options) do
    {:ok, metadata_handle} =
      ReqLLM.StreamResponse.MetadataHandle.start_link(fn ->
        %{
          response_id: "offline-partial-stream",
          finish_reason: :stop,
          usage: %{input_tokens: 8, output_tokens: 1, total_cost: 0.001}
        }
      end)

    stream =
      Stream.concat(
        [ReqLLM.StreamChunk.text("partial")],
        Stream.map([:interrupt], fn :interrupt ->
          raise "offline stream interrupted"
        end)
      )

    {:ok,
     %ReqLLM.StreamResponse{
       stream: stream,
       metadata_handle: metadata_handle,
       cancel: fn -> :ok end,
       model: model,
       context: context
     }}
  end

  def stream_text(model, context, options), do: Offline.stream_text(model, context, options)

  @impl true
  defdelegate generate_object(model, context, schema, options), to: Offline

  @impl true
  defdelegate stream_object(model, context, schema, options), to: Offline

  @impl true
  defdelegate generate_image(model, prompt, options), to: Offline

  @impl true
  defdelegate stream_image(model, prompt, options), to: Offline

  @impl true
  defdelegate generate_video(model, content, options), to: Offline

  @impl true
  defdelegate query_video(model, task_id, options), to: Offline

  @impl true
  defdelegate wait_video(model, task_id, options), to: Offline

  @impl true
  defdelegate retrieve_video_file(model, file_id, options), to: Offline

  @impl true
  defdelegate upload_video_file(model, file, options), to: Offline

  @impl true
  defdelegate embed(model, input, options), to: Offline

  @impl true
  defdelegate rerank(model, options), to: Offline

  @impl true
  defdelegate compact_context(model, context, options), to: Offline

  @impl true
  defdelegate evaluate(model, state, questions, options), to: Offline

  @impl true
  defdelegate evaluation_models(), to: Offline

  @impl true
  defdelegate ocr(model, document, options), to: Offline

  @impl true
  defdelegate ocr_file(model, path, options), to: Offline

  @impl true
  defdelegate transcribe(model, audio, options), to: Offline

  @impl true
  defdelegate transcribe_detailed(model, audio, options), to: Offline

  @impl true
  defdelegate speak(model, text, options), to: Offline

  @impl true
  defdelegate speak_detailed(model, text, options), to: Offline

  defp repair_request?(context) do
    context
    |> ReqLLM.Context.to_list()
    |> Enum.any?(fn message ->
      message.role == :system and get_in(message.metadata, [:jido, :source, :type]) == :output_repair
    end)
  end

  defp response(model, context, text, finish_reason) do
    message = ReqLLM.Context.assistant(text)

    %ReqLLM.Response{
      id: "offline-#{String.replace(model, ":", "-")}",
      model: model,
      context: ReqLLM.Context.append(context, message),
      finish_reason: finish_reason,
      message: message,
      usage: %{input_tokens: 8, output_tokens: 4, total_cost: 0.001}
    }
  end

  defp tool_response(model, context, call) do
    message = ReqLLM.Context.assistant("", tool_calls: [call])

    %ReqLLM.Response{
      id: "offline-tool-request",
      model: model,
      context: ReqLLM.Context.append(context, message),
      finish_reason: :tool_calls,
      message: message,
      usage: %{input_tokens: 8, output_tokens: 4, total_cost: 0.001}
    }
  end
end

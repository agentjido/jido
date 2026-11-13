Code.require_file("../../support/offline_inference_client.ex", __DIR__)

defmodule Jido.Examples.RAG.ToolClient do
  @moduledoc "Requests one local retrieval tool, then returns a cited answer."
  @behaviour Jido.AI.InferenceClient

  alias Jido.Examples.Support.OfflineInferenceClient, as: Offline

  @impl true
  def generate_text(model, context, _options) do
    if Enum.any?(ReqLLM.Context.to_list(context), &(&1.role == :tool)) do
      response(model, context, ReqLLM.Context.assistant("The policy limit is 30 days [doc-1]."), :stop)
    else
      call = ReqLLM.ToolCall.new("rag-lookup-1", "rag_lookup_policy", ~s({"query":"retention limit"}))
      response(model, context, ReqLLM.Context.assistant("", tool_calls: [call]), :tool_calls)
    end
  end

  defp response(model, context, message, finish_reason) do
    {:ok,
     %ReqLLM.Response{
       id: "offline-rag-tool",
       model: model,
       context: ReqLLM.Context.append(context, message),
       message: message,
       finish_reason: finish_reason,
       usage: %{input_tokens: 8, output_tokens: 4}
     }}
  end

  @impl true
  defdelegate stream_text(model, context, options), to: Offline

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
end

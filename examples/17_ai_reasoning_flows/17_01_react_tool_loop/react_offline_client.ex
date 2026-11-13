defmodule Jido.Examples.AI.ReActOfflineClient do
  @moduledoc "Requests two local tools, then returns one deterministic answer."

  @behaviour Jido.AI.InferenceClient

  alias Jido.Examples.Support.OfflineInferenceClient, as: Offline

  @impl true
  def generate_text(model, context, _options) do
    if Enum.any?(ReqLLM.Context.to_list(context), &(&1.role == :tool)) do
      response(model, context, ReqLLM.Context.assistant("Results: 5 and 20."), :stop)
    else
      calls = [
        ReqLLM.ToolCall.new("add-1", "add", ~s({"left":2,"right":3})),
        ReqLLM.ToolCall.new("multiply-1", "multiply", ~s({"left":4,"right":5}))
      ]

      response(model, context, ReqLLM.Context.assistant("", tool_calls: calls), :tool_calls)
    end
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

  defp response(model, context, message, finish_reason) do
    {:ok,
     %ReqLLM.Response{
       id: "offline-react",
       model: model,
       context: ReqLLM.Context.append(context, message),
       finish_reason: finish_reason,
       message: message,
       usage: %{input_tokens: 8, output_tokens: 4}
     }}
  end
end

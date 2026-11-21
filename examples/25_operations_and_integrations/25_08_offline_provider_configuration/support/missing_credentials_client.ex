defmodule Jido.Examples.Operations.MissingCredentialsClient do
  @moduledoc "Returns one deterministic authorization failure without a live provider."

  @behaviour Jido.AI.InferenceClient

  alias Jido.Examples.Support.OfflineInferenceClient, as: Offline

  @impl true
  def generate_text(_model, _context, _options) do
    {:error,
     ReqLLM.Error.API.Request.exception(
       reason: "offline authorization failure",
       status: 401,
       request_body: %{credential: "fake-secret-must-not-appear"}
     )}
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

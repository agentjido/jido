defmodule Jido.AI.InferenceClient.ReqLLM do
  @moduledoc "The default ReqLLM implementation of the Jido AI inference client."

  @behaviour Jido.AI.InferenceClient

  @impl true
  def generate_text(model, messages, opts), do: ReqLLM.generate_text(model, messages, opts)

  @impl true
  def stream_text(model, messages, opts), do: ReqLLM.stream_text(model, messages, opts)

  @impl true
  def generate_object(model, messages, schema, opts) do
    ReqLLM.generate_object(model, messages, schema, opts)
  end

  @impl true
  def generate_image(model, prompt_or_messages, opts) do
    ReqLLM.generate_image(model, prompt_or_messages, opts)
  end

  @impl true
  def stream_image(model, prompt_or_messages, opts) do
    ReqLLM.stream_image(model, prompt_or_messages, opts)
  end

  @impl true
  def generate_video(model, content, opts), do: ReqLLM.generate_video(model, content, opts)

  @impl true
  def query_video(model, task_id, opts), do: ReqLLM.query_video(model, task_id, opts)

  @impl true
  def wait_video(model, task_id, opts), do: ReqLLM.wait_video(model, task_id, opts)

  @impl true
  def retrieve_video_file(model, file_id, opts) do
    ReqLLM.retrieve_video_file(model, file_id, opts)
  end

  @impl true
  def upload_video_file(model, file_binary, opts) do
    ReqLLM.upload_video_file(model, file_binary, opts)
  end

  @impl true
  def stream_object(model, messages, schema, opts) do
    ReqLLM.stream_object(model, messages, schema, opts)
  end

  @impl true
  def embed(model, input, opts), do: ReqLLM.embed(model, input, opts)

  @impl true
  def rerank(model, opts), do: ReqLLM.rerank(model, opts)

  @impl true
  def compact_context(model, messages, opts) do
    ReqLLM.compact_context(model, messages, opts)
  end

  @impl true
  def evaluate(model, state, questions, opts) do
    ReqLLM.evaluate(model, state, questions, opts)
  end

  @impl true
  def evaluation_models, do: ReqLLM.evaluation_models()

  @impl true
  def ocr(model, document_binary, opts), do: ReqLLM.ocr(model, document_binary, opts)

  @impl true
  def ocr_file(model, path, opts), do: ReqLLM.ocr_file(model, path, opts)

  @impl true
  def transcribe(model, audio, opts), do: ReqLLM.transcribe(model, audio, opts)

  @impl true
  def transcribe_detailed(model, audio, opts) do
    ReqLLM.transcribe_detailed(model, audio, opts)
  end

  @impl true
  def speak(model, text, opts), do: ReqLLM.speak(model, text, opts)

  @impl true
  def speak_detailed(model, text, opts), do: ReqLLM.speak_detailed(model, text, opts)
end

defmodule Jido.Examples.Support.OfflineInferenceClient do
  @moduledoc "A deterministic, no-network inference client for the example suite."

  @behaviour Jido.AI.InferenceClient

  @impl true
  def generate_text(model, context, options) do
    text = Keyword.get(options, :offline_response, response_for(model))
    {:ok, response(model, context, text, "offline-text")}
  end

  @impl true
  def stream_text(_model, _context, _options), do: {:error, :offline_stream_fixture_required}

  @impl true
  def generate_object(model, context, _schema, options) do
    value = Keyword.get(options, :offline_object, %{"status" => "ok"})
    {:ok, response(model, context, JSON.encode!(value), "offline-object")}
  end

  @impl true
  def stream_object(_model, _context, _schema, _options),
    do: {:error, :offline_stream_fixture_required}

  @impl true
  def generate_image(model, prompt, _options),
    do: {:ok, %{kind: :image, model: model, prompt: prompt, bytes: <<"offline-image">>}}

  @impl true
  def stream_image(_model, _prompt, _options), do: {:error, :offline_stream_fixture_required}

  @impl true
  def generate_video(model, content, _options),
    do: {:ok, %{kind: :video, model: model, content: content, task_id: "offline-video-1"}}

  @impl true
  def query_video(_model, task_id, _options), do: {:ok, %{task_id: task_id, status: :completed}}

  @impl true
  def wait_video(_model, task_id, _options),
    do: {:ok, %{task_id: task_id, status: :completed, file_id: "offline-file-1"}}

  @impl true
  def retrieve_video_file(_model, file_id, _options),
    do: {:ok, %{file_id: file_id, bytes: <<"offline-video">>}}

  @impl true
  def upload_video_file(_model, file, _options),
    do: {:ok, %{file_id: "offline-upload-1", bytes: byte_size(file)}}

  @impl true
  def embed(_model, input, _options) when is_binary(input), do: {:ok, vector(input)}

  def embed(_model, inputs, _options) when is_list(inputs),
    do: {:ok, Enum.map(inputs, &vector/1)}

  @impl true
  def rerank(_model, options) do
    documents = Keyword.get(options, :documents, [])
    {:ok, Enum.with_index(documents, &%{document: &1, score: 1.0 - &2 / 100})}
  end

  @impl true
  def compact_context(_model, context, options) do
    {:ok,
     %{
       summary: Keyword.get(options, :offline_summary, "Offline compacted history"),
       source_messages: length(ReqLLM.Context.to_list(context))
     }}
  end

  @impl true
  def evaluate(model, state, questions, _options) do
    text = "offline judge: #{map_size(questions)} checks"
    context = ReqLLM.Context.new([ReqLLM.Context.user(inspect(state))])
    {:ok, response(model, context, text, "offline-evaluation")}
  end

  @impl true
  def evaluation_models, do: ["offline:judge"]

  @impl true
  def ocr(_model, document, _options),
    do: {:ok, %{text: "OFFLINE OCR", bytes: byte_size(document)}}

  @impl true
  def ocr_file(_model, path, _options), do: {:ok, %{text: "OFFLINE OCR", path: path}}

  @impl true
  def transcribe(_model, _audio, _options), do: {:ok, "offline transcript"}

  @impl true
  def transcribe_detailed(_model, _audio, _options),
    do: {:ok, %{text: "offline transcript", segments: []}}

  @impl true
  def speak(_model, text, _options), do: {:ok, <<"offline speech:", text::binary>>}

  @impl true
  def speak_detailed(_model, text, _options),
    do: {:ok, %{audio: <<"offline speech:", text::binary>>, format: :binary}}

  defp response(model, context, text, id) do
    %ReqLLM.Response{
      id: id,
      model: model,
      context: context,
      finish_reason: :stop,
      message: ReqLLM.Context.assistant(text)
    }
  end

  defp response_for("offline:guardrails"), do: "Safe offline answer"
  defp response_for("offline:rag"), do: "The policy limit is 30 days [doc-1]."
  defp response_for("offline:compact"), do: "Offline compacted history"
  defp response_for("offline:judge"), do: "pass"
  defp response_for(_model), do: "Offline response"

  defp vector(text) do
    hash = :erlang.phash2(text, 10_000)
    [hash / 10_000, byte_size(text) / 1_000]
  end
end

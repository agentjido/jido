defmodule Jido.Examples.AI.MediaOperations.GenerateImage do
  @moduledoc "Runs one application-owned image-generation operation."

  alias Jido.Joi

  use Jido.Action,
    name: "examples_ai_media_generate_image",
    schema:
      Joi.object(%{
        model: Joi.string(),
        prompt: Joi.string()
      }),
    output_schema:
      Joi.object(%{
        bytes: Joi.integer() |> Joi.min(0),
        kind: Joi.enum([:image])
      })

  @impl true
  def run(input, context) do
    client = Jido.AI.InferenceClient.Selection.client!(context)

    with {:ok, result} <- client.generate_image(input.model, input.prompt, []) do
      {:ok, %{bytes: byte_size(result.bytes), kind: result.kind}}
    end
  end
end

defmodule Jido.Examples.AI.MediaOperations.ReadDocument do
  @moduledoc "Runs OCR through the selected inference client."

  alias Jido.Joi

  use Jido.Action,
    name: "examples_ai_media_read_document",
    schema:
      Joi.object(%{
        document: Joi.string(),
        model: Joi.string()
      }),
    output_schema:
      Joi.object(%{
        bytes: Joi.integer() |> Joi.min(0),
        text: Joi.string()
      })

  @impl true
  def run(input, context) do
    client = Jido.AI.InferenceClient.Selection.client!(context)
    client.ocr(input.model, input.document, [])
  end
end

defmodule Jido.Examples.AI.MediaOperations.SpeechRoundTrip do
  @moduledoc "Creates speech, then transcribes the local result."

  alias Jido.Joi

  use Jido.Action,
    name: "examples_ai_media_speech_round_trip",
    schema:
      Joi.object(%{
        model: Joi.string(),
        text: Joi.string()
      }),
    output_schema:
      Joi.object(%{
        audio_bytes: Joi.integer() |> Joi.min(0),
        transcript: Joi.string()
      })

  @impl true
  def run(input, context) do
    client = Jido.AI.InferenceClient.Selection.client!(context)

    with {:ok, audio} <- client.speak(input.model, input.text, []),
         {:ok, transcript} <- client.transcribe(input.model, audio, []) do
      {:ok, %{audio_bytes: byte_size(audio), transcript: transcript}}
    end
  end
end

defmodule Jido.Examples.AI.MediaOperations.GenerateVideo do
  @moduledoc "Starts, waits for, and retrieves one video operation."

  alias Jido.Joi

  use Jido.Action,
    name: "examples_ai_media_generate_video",
    schema:
      Joi.object(%{
        model: Joi.string(),
        prompt: Joi.string()
      }),
    output_schema:
      Joi.object(%{
        bytes: Joi.integer() |> Joi.min(0),
        task_id: Joi.string()
      })

  @impl true
  def run(input, context) do
    client = Jido.AI.InferenceClient.Selection.client!(context)

    with {:ok, task} <- client.generate_video(input.model, input.prompt, []),
         {:ok, completed} <- client.wait_video(input.model, task.task_id, []),
         {:ok, file} <- client.retrieve_video_file(input.model, completed.file_id, []) do
      {:ok, %{bytes: byte_size(file.bytes), task_id: task.task_id}}
    end
  end
end

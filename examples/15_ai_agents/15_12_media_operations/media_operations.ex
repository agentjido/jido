defmodule Jido.Examples.AI.MediaOperations do
  @moduledoc "Runs image, OCR, speech, transcription, and video as normal Flow work."

  alias Jido.Joi

  use Jido.Flow,
    name: "examples_ai_media_operations",
    schema:
      Joi.object(%{
        document: Joi.string(),
        model: Joi.string() |> Joi.min(1),
        prompt: Joi.string() |> Joi.min(1)
      }),
    output_schema:
      Joi.object(%{
        image: Joi.map(),
        ocr: Joi.map(),
        speech: Joi.map(),
        video: Joi.map()
      })

  flow do
    step "image",
      action: Jido.Examples.AI.MediaOperations.GenerateImage,
      params: %{model: input(:model), prompt: input(:prompt)}

    step "ocr",
      action: Jido.Examples.AI.MediaOperations.ReadDocument,
      params: %{document: input(:document), model: input(:model)}

    step "speech",
      action: Jido.Examples.AI.MediaOperations.SpeechRoundTrip,
      params: %{model: input(:model), text: input(:prompt)}

    step "video",
      action: Jido.Examples.AI.MediaOperations.GenerateVideo,
      params: %{model: input(:model), prompt: input(:prompt)}

    step "collect",
         values <- %{
           image: result("image"),
           ocr: result("ocr"),
           speech: result("speech"),
           video: result("video")
         } do
      {:ok, values}
    end

    output result("collect")
  end
end

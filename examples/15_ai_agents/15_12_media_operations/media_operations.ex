defmodule Jido.Examples.AI.MediaOperations do
  @moduledoc "Runs image, OCR, speech, transcription, and video as normal Flow work."

  use Jido.Flow,
    name: "examples_ai_media_operations",
    schema:
      Jido.Joi.object(%{
        document: Jido.Joi.string(),
        model: Jido.Joi.string() |> Jido.Joi.min(1),
        prompt: Jido.Joi.string() |> Jido.Joi.min(1)
      }),
    output_schema:
      Jido.Joi.object(%{
        image: Jido.Joi.map(),
        ocr: Jido.Joi.map(),
        speech: Jido.Joi.map(),
        video: Jido.Joi.map()
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

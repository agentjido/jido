defmodule Jido.Examples.AI.MultimodalContent.Agent do
  @moduledoc "Accepts portable text and image content parts in one AI request."

  use Jido.AI.Agent, name: "examples_ai_multimodal_content_agent"

  ai do
    reasoning Jido.AI.Reasoning.ReAct do
      model "offline:multimodal"
      instructions "Describe the supplied content."

      limits do
        model_calls 1
        retries 0
        elapsed_ms(5_000)
      end
    end
  end

  @doc "Builds one portable text-and-image request."
  def request(text, image_url, media_type) do
    request_signal(%{
      input: [
        %{type: :text, text: text},
        %{type: :image_url, url: image_url, media_type: media_type}
      ],
      options: %{offline_response: "The offline image contains a blue square."}
    })
  end
end

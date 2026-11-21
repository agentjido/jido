defmodule Jido.AI.InferenceClient do
  @moduledoc """
  Defines the model execution boundary used by Jido AI.

  `Jido.AI.InferenceClient.Selection` owns configured-client selection and
  validation. This module owns only the implementation contract.
  """

  @type model :: ReqLLM.model_input()
  @type generation_model :: ReqLLM.generation_model_input()
  @type prompt :: ReqLLM.Context.prompt()
  @type result(response) :: {:ok, response} | {:error, term()}

  @callback generate_text(generation_model(), prompt(), keyword()) :: result(ReqLLM.Response.t())
  @callback stream_text(generation_model(), prompt(), keyword()) ::
              result(ReqLLM.StreamResponse.t())
  @callback generate_object(generation_model(), prompt(), term(), keyword()) ::
              result(ReqLLM.Response.t())
  @callback generate_image(model(), term(), keyword()) :: result(term())
  @callback stream_image(model(), term(), keyword()) :: result(term())
  @callback generate_video(model(), term(), keyword()) :: result(term())
  @callback query_video(model(), String.t(), keyword()) :: result(term())
  @callback wait_video(model(), String.t(), keyword()) :: result(term())
  @callback retrieve_video_file(model(), String.t() | integer(), keyword()) :: result(term())
  @callback upload_video_file(model(), binary(), keyword()) :: result(term())
  @callback stream_object(generation_model(), prompt(), term(), keyword()) ::
              result(ReqLLM.StreamResponse.t())
  @callback embed(ReqLLM.model_input(), String.t() | [String.t()], keyword()) ::
              result(term())
  @callback rerank(ReqLLM.model_input(), keyword()) :: result(term())
  @callback compact_context(model(), prompt(), keyword()) :: result(term())
  @callback evaluate(ReqLLM.model_input(), term(), map(), keyword()) ::
              result(ReqLLM.Response.t())
  @callback evaluation_models() :: [String.t()]
  @callback ocr(ReqLLM.model_input(), binary(), keyword()) :: result(term())
  @callback ocr_file(ReqLLM.model_input(), Path.t(), keyword()) :: result(term())
  @callback transcribe(ReqLLM.model_input(), term(), keyword()) :: result(term())
  @callback transcribe_detailed(ReqLLM.model_input(), term(), keyword()) :: result(term())
  @callback speak(ReqLLM.model_input(), String.t(), keyword()) :: result(term())
  @callback speak_detailed(ReqLLM.model_input(), String.t(), keyword()) :: result(term())
end

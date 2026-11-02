defmodule Jido.AI.InferenceClient do
  @moduledoc """
  Defines the model execution boundary used by Jido AI.

  Applications can configure an implementation with `:ai_inference_client` in the
  `:jido` application environment. A Jido action context can override that
  implementation with `:jido_ai_inference_client`.
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

  @default_client Jido.AI.InferenceClient.ReqLLM
  @callbacks [
    generate_text: 3,
    stream_text: 3,
    generate_object: 4,
    generate_image: 3,
    stream_image: 3,
    generate_video: 3,
    query_video: 3,
    wait_video: 3,
    retrieve_video_file: 3,
    upload_video_file: 3,
    stream_object: 4,
    embed: 3,
    rerank: 2,
    compact_context: 3,
    evaluate: 4,
    evaluation_models: 0,
    ocr: 3,
    ocr_file: 3,
    transcribe: 3,
    transcribe_detailed: 3,
    speak: 3,
    speak_detailed: 3
  ]

  @doc "Returns the configured inference client for one action context."
  @spec client!(map()) :: module()
  def client!(context \\ %{}) when is_map(context) do
    context
    |> Map.get(
      :jido_ai_inference_client,
      Application.get_env(:jido, :ai_inference_client, @default_client)
    )
    |> validate_client!()
  end

  defp validate_client!(client) when is_atom(client) do
    if Code.ensure_loaded?(client) and
         Enum.all?(@callbacks, fn {name, arity} -> function_exported?(client, name, arity) end) do
      client
    else
      raise ArgumentError, "invalid Jido AI inference client: #{inspect(client)}"
    end
  end

  defp validate_client!(client) do
    raise ArgumentError, "invalid Jido AI inference client: #{inspect(client)}"
  end
end

defmodule Jido.AI.InferenceClient.Selection do
  @moduledoc "Selects and validates the inference client for one AI operation."

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

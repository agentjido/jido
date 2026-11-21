defmodule Jido.AI.InferenceClient.Selection do
  @moduledoc "Selects and validates the inference client for one AI operation."

  @default_client Jido.AI.InferenceClient.ReqLLM

  @callbacks Jido.AI.InferenceClient.behaviour_info(:callbacks)

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

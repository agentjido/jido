defmodule Jido.AI.Actions.Embed do
  @moduledoc "Generates one embedding or a batch of embeddings."

  alias Jido.AI.{InferenceClient, Usage}

  use Jido.Action,
    id: "jido.ai/actions/embed",
    vsn: 1,
    name: "jido_ai_embed",
    description: "Generate embeddings with ReqLLM",
    schema:
      Zoi.object(%{
        model: Zoi.string() |> Zoi.default("openai:text-embedding-3-small"),
        input: Zoi.union([Zoi.string(), Zoi.list(Zoi.string())]),
        options: Zoi.map() |> Zoi.default(%{})
      }),
    output_schema: Zoi.map()

  @impl Jido.Action
  def run(%{model: model, input: input, options: options}, context) do
    options = options |> Map.to_list() |> Keyword.put(:return_usage, true)

    client = InferenceClient.client!(context)

    case client.embed(model, input, options) do
      {:ok, %{embedding: embedding, usage: usage}} ->
        {:ok, %{embedding: embedding, usage: Usage.normalize(usage)}}

      {:error, reason} ->
        {:error, reason}
    end
  end
end

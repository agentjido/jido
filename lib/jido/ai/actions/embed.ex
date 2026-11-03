defmodule Jido.AI.Actions.Embed do
  alias Jido.Joi
  @moduledoc "Generates one embedding or a batch of embeddings."

  alias Jido.AI.InferenceClient.Selection
  alias Jido.AI.Usage

  use Jido.Action,
    id: "jido.ai/actions/embed",
    vsn: 1,
    name: "jido_ai_embed",
    description: "Generate embeddings with ReqLLM",
    schema:
      Joi.object(%{
        model: Joi.string() |> Joi.default("openai:text-embedding-3-small"),
        input: Joi.union([Joi.string(), Joi.list(Joi.string())]),
        options: Joi.map() |> Joi.default(%{})
      }),
    output_schema: Joi.map()

  @impl Jido.Action
  def run(%{model: model, input: input, options: options}, context) do
    options = options |> Map.to_list() |> Keyword.put(:return_usage, true)

    client = Selection.client!(context)

    case client.embed(model, input, options) do
      {:ok, %{embedding: embedding, usage: usage}} ->
        {:ok, %{embedding: embedding, usage: Usage.normalize(usage)}}

      {:error, reason} ->
        {:error, reason}
    end
  end
end

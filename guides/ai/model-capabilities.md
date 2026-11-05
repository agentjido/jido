# Model Capabilities

This reference states which model features Jido AI uses and where to check that a model supports them. Jido does not check model capabilities itself. It sends the request, and the provider or ReqLLM reports any mismatch as a model error.

## What Jido calls

`Jido.AI.InferenceClient` has 22 callbacks. Jido uses three of them.

| Callback | Called by | When |
| --- | --- | --- |
| `generate_text/3` | Each built-in reasoning Flow, through `Jido.AI.Reasoning.Actions.CallModel` | Each model call |
| `stream_text/3` | `Jido.AI.Reasoning.Actions.CallModel` | A request sets `stream: true` |
| `embed/3` | `Jido.AI.Actions.Embed` | The Action runs |

The other callbacks exist so that a client can serve the same ReqLLM surface. Jido has no Action or Flow for them. They are `generate_object/4`, `stream_object/4`, `generate_image/3`, `stream_image/3`, `generate_video/3`, `query_video/3`, `wait_video/3`, `retrieve_video_file/3`, `upload_video_file/3`, `rerank/2`, `compact_context/3`, `evaluate/4`, `evaluation_models/0`, `ocr/3`, `ocr_file/3`, `transcribe/3`, `transcribe_detailed/3`, `speak/3`, and `speak_detailed/3`. To use one, call `Jido.AI.InferenceClient.Selection.client!/1` from your own Action. Then the client your tests configure also serves that call.

## Features on a text call

| Feature | Request field | What the model must support | If the model lacks it |
| --- | --- | --- | --- |
| Tool calls | Agent `tools` | Tool calling | The request fails as a model error, or the model never calls a tool. |
| Forced tool use | `tool_policy.requirement` | Tool choice | Same as above. A final answer before any tool is rejected by the output guard. |
| Structured output | `output_schema` | JSON output | The output guard rejects a response with no `object`. |
| Streaming | `stream: true` | Streaming | ReqLLM reports the error. |
| Prompt caching | `prompt_cache` | Provider cache options | Jido sets these options only for `openai`, `anthropic`, `amazon_bedrock`, and `bedrock`. |
| Media input | `input` as a list of content parts | The media type | The provider reports the error. |

Failures from the provider follow the normal [retry and fallback path](react-reasoning.livemd), so a fallback model can serve a request after a retryable error. A non-retryable error fails the request without trying a fallback model.

Structured output matters when you pick a strategy. `Jido.AI.Reasoning.ChainOfThought`, `Jido.AI.Reasoning.ChainOfDraft`, `Jido.AI.Reasoning.AlgorithmOfThoughts`, `Jido.AI.Reasoning.TreeOfThoughts`, `Jido.AI.Reasoning.GraphOfThoughts`, and `Jido.AI.Reasoning.TRM` always send a JSON Schema. They need a model with structured output. See [Reasoning Strategies](reasoning-strategies.md).

## Check a model from the catalog

ReqLLM's model catalog holds capability data, and `ReqLLM.ModelHelpers` reads it. This lookup makes no network call. Catalog data can be missing for a model, and the helpers return `false` in that case, so treat `false` as "unknown or unsupported".

```elixir
alias ReqLLM.ModelHelpers

model = ReqLLM.model!("openai:gpt-4o-mini")

support = %{
  chat: ModelHelpers.chat?(model),
  tools: ModelHelpers.tools_enabled?(model),
  parallel_tools: ModelHelpers.tools_parallel?(model),
  json_schema: ModelHelpers.json_schema?(model),
  streaming_text: ModelHelpers.streaming_text?(model),
  reasoning: ModelHelpers.reasoning_enabled?(model)
}

true = Enum.all?(support, fn {_feature, value} -> is_boolean(value) end)
```

Check the model in your own code before you build a request, or at application start for a fixed list of models:

```elixir
alias ReqLLM.ModelHelpers

defmodule ModelCapabilitiesGuide.ModelCheck do
  
  def tools_ready?(model_name) do
    model = ReqLLM.model!(model_name)
    ModelHelpers.chat?(model) and ModelHelpers.tools_enabled?(model)
  end
end

true = is_boolean(ModelCapabilitiesGuide.ModelCheck.tools_ready?("anthropic:claude-haiku-4-5"))
```

## Send media input

`input` is a string or a list of content part maps. The input guard accepts a list when a part has text, or a non-empty `url`, `data`, or `file_id`. A string has a 2,000-character limit, and a list has a 2 MB limit on its encoded size. An input of only empty parts is blocked with `"input is empty"`.

The next example sends one text part and one image URL to a local client and shows what the model receives.

```elixir
defmodule ModelCapabilitiesGuide.LocalModel do
  @behaviour Jido.AI.InferenceClient

  @impl true
  def generate_text(model, context, _options) do
    types =
      context
      |> ReqLLM.Context.to_list()
      |> List.last()
      |> Map.fetch!(:content)
      |> Enum.map_join(",", &Atom.to_string(&1.type))

    {:ok,
     %ReqLLM.Response{
       id: "local",
       model: model,
       context: context,
       message: ReqLLM.Context.assistant("Parts: #{types}"),
       finish_reason: :stop,
       usage: %{input_tokens: 4, output_tokens: 3}
     }}
  end

  @impl true
  def evaluation_models, do: []

  for {name, arity} <- Jido.AI.InferenceClient.behaviour_info(:callbacks),
      {name, arity} not in [generate_text: 3, evaluation_models: 0] do
    @impl true
    def unquote(name)(unquote_splicing(Macro.generate_arguments(arity, __MODULE__))),
      do: {:error, :not_supported}
  end
end

defmodule ModelCapabilitiesGuide.DamageAgent do
  use Jido.AI.Agent, name: "damage_agent"

  ai do
    reasoning Jido.AI.Reasoning.ReAct
  end
end

agent = ModelCapabilitiesGuide.DamageAgent.instantiate!(id: "damage-1")

input = [
  %{type: :text, text: "Describe the damage in this photo."},
  %{type: :image_url, url: "https://example.test/parcel.jpg"}
]

{:ok, _agent, [%{signal: reply}]} =
  ModelCapabilitiesGuide.DamageAgent.cmd(
    agent,
    ModelCapabilitiesGuide.DamageAgent.request_signal!(%{input: input}),
    context: %{jido_ai_inference_client: ModelCapabilitiesGuide.LocalModel}
  )

%{status: :completed, output: "Parts: text,image_url"} = reply.data
```

## Related

- [Inference Clients](inference-clients.md)
- [Configure ReqLLM](req-llm-configuration.livemd)
- [Reasoning Matrix](../reference/reasoning-strategy-matrix.md)

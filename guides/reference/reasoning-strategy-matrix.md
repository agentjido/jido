# Reasoning Matrix

This guide compares the eight reasoning Flows in `Jido.AI.Reasoning`, field by field. For help choosing one, see [Reasoning Strategies](../ai/reasoning-strategies.md). For the fields of a request, see [Reasoning Setup](../ai/reasoning-flows-models-and-limits.md).

## Behavior

| Flow | Flow ID | Model calls | Agent tools | Retries and `fallback_models` | Streaming | Repair of a bad answer | `output` comes from |
| --- | --- | --- | --- | --- | --- | --- | --- |
| `Jido.AI.Reasoning.ReAct` | `jido.ai/reasoning/react` | Up to `limits.model_calls` | Yes | Yes | With `stream: true` | Yes | Model text, or the object for `output_schema` |
| `Jido.AI.Reasoning.ChainOfThought` | `jido.ai/reasoning/chain-of-thought` | 1 | No | No | No | No | `conclusion` |
| `Jido.AI.Reasoning.ChainOfDraft` | `jido.ai/reasoning/chain-of-draft` | 1 | No | No | No | No | `answer` |
| `Jido.AI.Reasoning.AlgorithmOfThoughts` | `jido.ai/reasoning/algorithm-of-thoughts` | 1 | No | No | No | No | `answer` |
| `Jido.AI.Reasoning.TreeOfThoughts` | `jido.ai/reasoning/tree-of-thoughts` | 3 | No | No | No | No | `answer` of the third call |
| `Jido.AI.Reasoning.GraphOfThoughts` | `jido.ai/reasoning/graph-of-thoughts` | 2 | No | No | No | No | `answer` of the second call |
| `Jido.AI.Reasoning.TRM` | `jido.ai/reasoning/trm` | 3 | No | No | No | No | `answer` of the third call |
| `Jido.AI.Reasoning.Adaptive` | `jido.ai/reasoning/adaptive` | That of the selected Flow | That of the selected Flow | That of the selected Flow | That of the selected Flow | That of the selected Flow | That of the selected Flow |

All except `ReAct` send a fixed JSON Schema with each call, so the model and client must support structured output. See [Model Capabilities](../ai/model-capabilities.md).

## Input fields

| Field | `ReAct` | Structured Flows | `Adaptive` |
| --- | --- | --- | --- |
| `input` | Required | Required | Required |
| `instructions`, `model`, `options`, `prompt_cache`, `context`, `limits` | Yes | Yes | Yes, optional and passed to the selected Flow |
| `fallback_models`, `stream`, `output_schema`, `review_tools`, `tool_policy` | Yes | No | No |
| `strategy` | No | No | Yes, optional, and it skips selection |

"Structured Flows" means `ChainOfThought`, `ChainOfDraft`, `AlgorithmOfThoughts`, `TreeOfThoughts`, `GraphOfThoughts`, and `TRM`. `ReAct` and the structured Flows reject unknown top-level fields. `Adaptive` forwards them, so the selected Flow rejects them.

## Input defaults

| Flow | `options` default |
| --- | --- |
| `ReAct` | `%{}` |
| `ChainOfThought` | `%{max_tokens: 512, temperature: 0.0, receive_timeout: 30_000}` |
| `ChainOfDraft` | `%{max_tokens: 256, temperature: 0.0}` |
| `AlgorithmOfThoughts` | `%{max_tokens: 1024, temperature: 0.0}` |
| `TreeOfThoughts` | `%{max_tokens: 1536, temperature: 0.4}` |
| `GraphOfThoughts` | `%{max_tokens: 1536, temperature: 0.3}` |
| `TRM` | `%{max_tokens: 1536, temperature: 0.2}` |
| `Adaptive` | None. The selected Flow's default applies. |

Every Flow other than `Adaptive` defaults to:

| Field | Default |
| --- | --- |
| `model` | `"openai:gpt-4o-mini"` |
| `prompt_cache` | `%{enabled: false}` |
| `context` | `%{max_messages: 64, max_bytes: 200_000}` |

The defaults above are read from each Flow's contract, as this check shows.

```elixir
alias Jido.AI.Reasoning.{
  Adaptive,
  AlgorithmOfThoughts,
  ChainOfDraft,
  ChainOfThought,
  GraphOfThoughts,
  ReAct,
  TreeOfThoughts,
  TRM
}

option_default = fn flow, field ->
  flow.authoring_contract()["input_schema"]["properties"][field]["default"]
end

%{} = option_default.(ReAct, "options")
%{"max_tokens" => 512, "temperature" => +0.0, "receive_timeout" => 30_000} = option_default.(ChainOfThought, "options")
%{"max_tokens" => 256, "temperature" => +0.0} = option_default.(ChainOfDraft, "options")
%{"max_tokens" => 1024, "temperature" => +0.0} = option_default.(AlgorithmOfThoughts, "options")
%{"max_tokens" => 1536, "temperature" => 0.4} = option_default.(TreeOfThoughts, "options")
%{"max_tokens" => 1536, "temperature" => 0.3} = option_default.(GraphOfThoughts, "options")
%{"max_tokens" => 1536, "temperature" => 0.2} = option_default.(TRM, "options")
nil = option_default.(Adaptive, "options")

"openai:gpt-4o-mini" = option_default.(TRM, "model")
%{"max_messages" => 64, "max_bytes" => 200_000} = option_default.(ReAct, "context")
```

## Limits

Set limits per request or in the `reasoning` block. See [Model Budgets and Usage](../ai/budgets-and-usage.md).

| Limit | `ReAct` default | Structured Flow default | Allowed range |
| --- | --- | --- | --- |
| `elapsed_ms` | `120_000` | `120_000` | 1 to 3,600,000 |
| `input_tokens`, `output_tokens`, `total_tokens` | `nil` (no limit) | `nil` (no limit) | 1 or more |
| `total_cost` | `nil` (no limit) | `nil` (no limit) | 0 or more |
| `model_calls` | `8` | Rejected | 1 to 16 |
| `tool_rounds` | `4` | Rejected | 0 to 8 |
| `tool_calls` | `8` | Rejected | 1 to 16 |
| `retries` | `1` | Rejected | 0 to 4 |
| `tool_output_bytes` | `16_384` | Rejected | 256 to 1,000,000 |

`Adaptive` accepts other limit keys so that it can forward them. The selected Flow then accepts or rejects them, so `limits.model_calls` fails unless the selection is `ReAct`.

## Results

Each Flow returns the same reply. Its `reasoning` field holds Flow-specific data, and `reasoning_steps` holds a count.

| Flow | `reasoning.method` | `reasoning` fields | `reasoning.phase` on recorded attempts |
| --- | --- | --- | --- |
| `ChainOfThought` | `:chain_of_thought` | `steps`, `steps_count`, `conclusion` | None |
| `ChainOfDraft` | `:chain_of_draft` | `drafts`, `steps_count`, `conclusion` | None |
| `AlgorithmOfThoughts` | `:algorithm_of_thoughts` | `operations`, `steps_count`, `conclusion` | None |
| `TreeOfThoughts` | `:tree_of_thoughts` | `thoughts`, `steps_count`, `conclusion` | `:generate`, `:evaluate`, `:synthesize` |
| `GraphOfThoughts` | `:graph_of_thoughts` | `nodes`, `edges`, `steps_count`, `conclusion` | `:construct`, `:synthesize` |
| `TRM` | `:trm` | `draft`, `critique`, `iterations`, `steps_count`, `conclusion` | `:draft`, `:critique`, `:revise` |

`ReAct` and `Adaptive` have no `reasoning` row. `Adaptive` returns the selected Flow's reply, and its `flow` field names that Flow.

A structured Flow ends with a terminal status in these cases:

| Case | `status` | `reason_code` |
| --- | --- | --- |
| The model call failed | `:failed` | `:model` |
| A budget ran out | `:blocked` | `:limits` |
| The output guard rejected the answer | `:blocked` | `:output` |
| `GraphOfThoughts` edges name a node ID that does not exist | `:blocked` | `:output` |

This run confirms the call counts, phases, and methods with a local client. It makes no network call.

```elixir
alias Jido.AI.Reasoning.{
  Adaptive,
  AlgorithmOfThoughts,
  ChainOfDraft,
  ChainOfThought,
  GraphOfThoughts,
  TreeOfThoughts,
  TRM
}

defmodule MatrixGuide.Client do
  @behaviour Jido.AI.InferenceClient

  def play(objects) do
    case Process.whereis(__MODULE__) do
      nil -> :ok
      pid -> Agent.stop(pid)
    end

    {:ok, _pid} = Agent.start_link(fn -> objects end, name: __MODULE__)
  end

  @impl true
  def generate_text(model, context, _options) do
    object = Agent.get_and_update(__MODULE__, fn [next | rest] -> {next, rest} end)

    {:ok,
     %ReqLLM.Response{
       id: "local",
       model: model,
       context: context,
       message: ReqLLM.Context.assistant(JSON.encode!(object)),
       object: object,
       finish_reason: :stop,
       usage: %{input_tokens: 10, output_tokens: 5}
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

run = fn flow, objects, input ->
  MatrixGuide.Client.play(objects)
  {:ok, result} = Jido.Exec.run(flow, %{input: input}, %{jido_ai_inference_client: MatrixGuide.Client})
  result.response
end

phases = fn response ->
  response.model_attempts |> Enum.map(& &1.reasoning[:phase]) |> Enum.reject(&is_nil/1)
end

question = "How should order 88 ship?"

cot = run.(ChainOfThought, [%{"steps" => [%{"number" => 1, "content" => "Use rail."}], "conclusion" => "Ship by rail."}], question)
%{status: :completed, model_calls: 1, output: "Ship by rail.", reasoning: %{method: :chain_of_thought}} = cot

cod = run.(ChainOfDraft, [%{"drafts" => ["Use rail"], "answer" => "Ship by rail."}], question)
%{model_calls: 1, reasoning: %{method: :chain_of_draft}} = cod

aot = run.(AlgorithmOfThoughts, [%{"operations" => ["List routes"], "answer" => "Ship by rail."}], question)
%{model_calls: 1, reasoning: %{method: :algorithm_of_thoughts}} = aot

tot =
  run.(
    TreeOfThoughts,
    [
      %{"thoughts" => [%{"content" => "Rail"}, %{"content" => "Air"}, %{"content" => "Road"}]},
      %{"thoughts" => [%{"content" => "Rail", "score" => 0.9}, %{"content" => "Air", "score" => 0.2}, %{"content" => "Road", "score" => 0.7}]},
      %{"answer" => "Ship by rail."}
    ],
    question
  )

%{model_calls: 3, reasoning: %{method: :tree_of_thoughts}} = tot
[:generate, :evaluate, :synthesize] = phases.(tot)

node = %{"id" => "rail", "content" => "Rail is cheap"}

got =
  run.(
    GraphOfThoughts,
    [%{"nodes" => [node], "edges" => []}, %{"answer" => "Ship by rail."}],
    question
  )

%{model_calls: 2, reasoning: %{method: :graph_of_thoughts}} = got
[:construct, :synthesize] = phases.(got)

bad_edge = %{"from" => "rail", "to" => "missing", "relationship" => "supports"}
blocked = run.(GraphOfThoughts, [%{"nodes" => [node], "edges" => [bad_edge]}], question)
%{status: :blocked, reason_code: :output} = blocked

trm =
  run.(
    TRM,
    [%{"draft" => "Rail."}, %{"critique" => "Add a reason."}, %{"answer" => "Rail, because it is cheapest."}],
    question
  )

%{model_calls: 3, reasoning: %{method: :trm, iterations: 1}} = trm
[:draft, :critique, :revise] = phases.(trm)

adaptive = run.(Adaptive, [%{"drafts" => ["Use rail"], "answer" => "Ship by rail."}], "Which route?")
%{flow: %{id: "jido.ai/reasoning/chain-of-draft"}} = adaptive

MatrixGuide.Client.play([])
{:error, _unknown_field} = Jido.Exec.run(Adaptive, %{input: "Which route?", tone: "formal"}, %{jido_ai_inference_client: MatrixGuide.Client})
```

## Adaptive selection

`Adaptive` splits the input into lowercase words and stops at the first matching row. It makes no model call to select.

| Input contains | Selected Flow |
| --- | --- |
| `puzzle`, `riddle`, `iterate`, `improve`, `refine`, `recursive` | `TRM` |
| `synthesize`, `combine`, `merge`, `integrate`, `relationships`, `perspectives` | `GraphOfThoughts` |
| `search`, `find`, `lookup`, `fetch`, `calculate`, `compute`, `execute`, `run`, `tool` | `ReAct` |
| `algorithm`, `backtrack`, `search-space`, `optimize` | `AlgorithmOfThoughts` |
| `analyze`, `explore`, `compare`, `evaluate`, `alternatives`, `options` | `TreeOfThoughts` |
| None, fewer than 12 words | `ChainOfDraft` |
| None, 12 words or more | `ChainOfThought` |

The `strategy` values are `:react`, `:chain_of_thought`, `:chain_of_draft`, `:algorithm_of_thoughts`, `:tree_of_thoughts`, `:graph_of_thoughts`, and `:trm`.

## Related

- [Reasoning Strategies](../ai/reasoning-strategies.md)
- [ReAct Reasoning](../ai/react-reasoning.livemd)
- [Custom Reasoning Flows](../ai/custom-reasoning-flows.livemd)

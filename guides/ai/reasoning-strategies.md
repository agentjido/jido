# Reasoning Strategies

This guide helps you choose a reasoning Flow. Each built-in strategy is an ordinary Flow, and each returns the same reply shape, so you can swap one in by changing the `reasoning` line.

## Compare the strategies

| Module | Model calls | Tools | Output |
| --- | --- | --- | --- |
| `Jido.AI.Reasoning.ReAct` | Up to `limits.model_calls` | Yes | Text, or the `output_schema` object |
| `Jido.AI.Reasoning.ChainOfThought` | 1 | No | `conclusion` |
| `Jido.AI.Reasoning.ChainOfDraft` | 1 | No | `answer` |
| `Jido.AI.Reasoning.AlgorithmOfThoughts` | 1 | No | `answer` |
| `Jido.AI.Reasoning.TreeOfThoughts` | 3 | No | `answer` |
| `Jido.AI.Reasoning.GraphOfThoughts` | 2 | No | `answer` |
| `Jido.AI.Reasoning.TRM` | 3 | No | `answer` |
| `Jido.AI.Reasoning.Adaptive` | That of the selected Flow | That of the selected Flow | That of the selected Flow |

Choose by what the task needs:

- Use `ReAct` when the model must call tools, or you need retries and fallback models.
- Use `ChainOfThought` for a visible, ordered list of reasoning steps.
- Use `ChainOfDraft` for the same with short draft steps and a smaller default token budget.
- Use `AlgorithmOfThoughts` for search or planning where you want the operations listed.
- Use `TreeOfThoughts` to generate candidates, score them, and keep the best two.
- Use `GraphOfThoughts` when the answer depends on relationships between ideas.
- Use `TRM` for a draft, a critique, and a revision.
- Use `Adaptive` when you cannot choose in advance and a keyword check is good enough.

[Reasoning Matrix](../reference/reasoning-strategy-matrix.md) has the full comparison.

## What the structured strategies share

All strategies other than `ReAct` work the same way:

- Each model call sends a fixed JSON Schema, so the model and client must support structured output. See [Model Capabilities](model-capabilities.md).
- They have no retries and no `fallback_models`. A failed call ends the request with `:failed`.
- An Agent's tools are not offered to the model, even if the Agent declares them.
- A response that fails the output guard ends the request with `:blocked` and reason code `:output`. There is no repair round.
- They accept `input`, `instructions`, `model`, `options`, `prompt_cache`, `context`, and `limits`. Their `limits` allow only `elapsed_ms`, `input_tokens`, `output_tokens`, `total_tokens`, `total_cost`, and `output_chars`. The Flow fixes the model call count, so `limits.model_calls` is an error.
- Their `options` default differs per Flow, in `temperature` and `max_tokens`. Check the Flow's source for the values. These `max_tokens` defaults stop an answer well below `limits.output_chars`, so raise both for long output. See [Output limits](budgets-and-usage.md#output-limits).
- Multi-call Flows keep only the final message in the conversation. Earlier phases are recorded as `:ai_model_attempt` entries with a `phase`.

The model reply's `reasoning` field holds the strategy data, and `reasoning_steps` holds its count.

| Strategy | `reasoning` fields | Phases recorded |
| --- | --- | --- |
| `ChainOfThought` | `method`, `steps`, `steps_count`, `conclusion` | none |
| `ChainOfDraft` | `method`, `drafts`, `steps_count`, `conclusion` | none |
| `AlgorithmOfThoughts` | `method`, `operations`, `steps_count`, `conclusion` | none |
| `TreeOfThoughts` | `method`, `thoughts`, `steps_count`, `conclusion` | `generate`, `evaluate`, `synthesize` |
| `GraphOfThoughts` | `method`, `nodes`, `edges`, `steps_count`, `conclusion` | `construct`, `synthesize` |
| `TRM` | `method`, `draft`, `critique`, `iterations`, `steps_count`, `conclusion` | `draft`, `critique`, `revise` |

`GraphOfThoughts` also blocks an answer whose edges point at node IDs that do not exist. `TRM` always runs one cycle, so `iterations` is 1.

## Run a structured strategy

A local client returns objects in the response's `:object` field. The real default client gets them from ReqLLM.

```elixir
defmodule StrategiesGuide.Objects do
  @behaviour Jido.AI.InferenceClient

  def play(objects) do
    case Process.whereis(__MODULE__) do
      nil -> :ok
      pid -> Agent.stop(pid)
    end

    {:ok, _pid} = Agent.start_link(fn -> objects end, name: __MODULE__)
  end

  @impl true
  def generate_text(model, context, options) do
    object = Agent.get_and_update(__MODULE__, fn [next | rest] -> {next, rest} end)
    false = Keyword.has_key?(options, :tools)

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

defmodule StrategiesGuide do
  def run(flow, objects, params) do
    StrategiesGuide.Objects.play(objects)
    {:ok, result} = Jido.Exec.run(flow, params, %{jido_ai_inference_client: StrategiesGuide.Objects})
    result.response
  end
end

defmodule StrategiesGuide.RouteAgent do
  use Jido.AI.Agent, name: "route_agent"

  ai do
    reasoning Jido.AI.Reasoning.ChainOfThought do
      model "openai:gpt-4o-mini"
    end
  end
end

StrategiesGuide.Objects.play([
  %{
    "steps" => [
      %{"number" => 1, "content" => "The order weighs 2 kg."},
      %{"number" => 2, "content" => "Rail is cheaper for that weight."}
    ],
    "conclusion" => "Ship by rail."
  }
])

agent = StrategiesGuide.RouteAgent.instantiate!(id: "route-1")

{:ok, agent, [%{signal: reply}]} =
  StrategiesGuide.RouteAgent.cmd(
    agent,
    StrategiesGuide.RouteAgent.request_signal!(%{input: "How should order 88 ship?"}),
    context: %{jido_ai_inference_client: StrategiesGuide.Objects}
  )

%{
  status: :completed,
  output: "Ship by rail.",
  model_calls: 1,
  reasoning_steps: 2,
  flow: %{id: "jido.ai/reasoning/chain-of-thought"},
  reasoning: %{method: :chain_of_thought, steps: [%{number: 1}, %{number: 2}]}
} = reply.data

{:ok, [%{role: :user}, %{role: :assistant}]} = Jido.AI.Thread.Projection.messages(agent.state.session)
```

## Run a multi-phase strategy

A multi-phase Flow makes one call for each phase. `TreeOfThoughts` scores its candidates in the second call and passes the two best to the third.

```elixir
tree =
  StrategiesGuide.run(
    Jido.AI.Reasoning.TreeOfThoughts,
    [
      %{"thoughts" => [%{"content" => "Rail"}, %{"content" => "Air"}, %{"content" => "Road"}]},
      %{
        "thoughts" => [
          %{"content" => "Rail", "score" => 0.9},
          %{"content" => "Air", "score" => 0.2},
          %{"content" => "Road", "score" => 0.7}
        ]
      },
      %{"answer" => "Ship by rail, with road as the backup."}
    ],
    %{input: "Compare shipping options."}
  )

%{status: :completed, output: "Ship by rail, with road as the backup.", model_calls: 3} = tree

[:generate, :evaluate, :synthesize] = Enum.map(tree.model_attempts, & &1.reasoning.phase)
```

## Select with Adaptive

`Jido.AI.Reasoning.Adaptive` picks one Flow from the words in the input. Set `strategy` to skip the check. The first matching row wins.

| Input contains a word from | Selected |
| --- | --- |
| `puzzle`, `riddle`, `iterate`, `improve`, `refine`, `recursive` | `TRM` |
| `synthesize`, `combine`, `merge`, `integrate`, `relationships`, `perspectives` | `GraphOfThoughts` |
| `search`, `find`, `lookup`, `fetch`, `calculate`, `compute`, `execute`, `run`, `tool` | `ReAct` |
| `algorithm`, `backtrack`, `search-space`, `optimize` | `AlgorithmOfThoughts` |
| `analyze`, `explore`, `compare`, `evaluate`, `alternatives`, `options` | `TreeOfThoughts` |
| none, under 12 words | `ChainOfDraft` |
| none, 12 words or more | `ChainOfThought` |

The check is plain keyword matching on lowercase words. It makes no model call, and it does not understand the request.

```elixir
drafted =
  StrategiesGuide.run(
    Jido.AI.Reasoning.Adaptive,
    [%{"drafts" => ["Order is late", "Offer credit"], "answer" => "Offer a credit."}],
    %{input: "What should we do?"}
  )

%{flow: %{id: "jido.ai/reasoning/chain-of-draft"}, output: "Offer a credit."} = drafted

forced =
  StrategiesGuide.run(
    Jido.AI.Reasoning.Adaptive,
    [%{"operations" => ["List routes", "Pick the cheapest"], "answer" => "Take route 2."}],
    %{input: "What should we do?", strategy: :algorithm_of_thoughts}
  )

%{flow: %{id: "jido.ai/reasoning/algorithm-of-thoughts"}, output: "Take route 2."} = forced
```

The reply's `flow` names the Flow that ran. `strategy` values are `:react`, `:chain_of_thought`, `:chain_of_draft`, `:algorithm_of_thoughts`, `:tree_of_thoughts`, `:graph_of_thoughts`, and `:trm`.

Input that fails the selected Flow's schema fails after selection. For example, `limits.model_calls` is valid when `ReAct` is selected and an error otherwise.

## Related

- [ReAct Reasoning](react-reasoning.livemd)
- [Custom Reasoning Flows](custom-reasoning-flows.livemd)
- [Reasoning Setup](reasoning-flows-models-and-limits.md)

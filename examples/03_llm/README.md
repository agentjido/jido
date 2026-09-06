# LLM examples

Follow the [ten-example sequence](../../test/examples/03_llm/README.md).
The shared `Jido.Examples.LLM.Adapter` contract belongs to these examples. It
is not a new SDK model API. Implement `call(client, operation, input)` and pass
`{module, client}` through caller context.

A minimal local model response:

```elixir
defmodule LocalModel do
  @behaviour Jido.Examples.LLM.Adapter
  def call(_client, :complete, %{prompt: prompt}), do: {:ok, %{answer: "Reply to: " <> prompt}}
end

{:ok, _} = Jido.start_link(name: LLMExample)
{:ok, server} = Jido.start_agent(LLMExample, Jido.Examples.ModelResponse)
Jido.Examples.ModelResponse.generate(server, "hello",
  context: %{model: {LocalModel, nil}})
```

Subagent Delegation uses `Jido.Examples.LLMSubagentDelegation`. Supply `:model`
for the parent planner and `:specialist` for the child model. The planner's
`:delegate` operation returns `%{role: "researcher", prompt: "task"}` or the
`"reviewer"` role. The child model's `:complete` operation receives that role
and prompt and returns `%{answer: "checked result"}`. Both return `{:ok, value}`
or `{:error, reason}`. The initial parent call returns pending state; the child
result commits in a later parent Turn. See the [integration tests](../../test/examples/03_llm/03_09_subagent_delegation/subagent_delegation_test.exs).

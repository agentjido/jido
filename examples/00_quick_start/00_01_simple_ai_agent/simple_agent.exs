Code.require_file("simple_agent.ex", __DIR__)

alias Jido.AI.Reasoning.ReAct
alias Jido.AI.Reasoning.ReAct.Actions
alias Jido.Examples.AI.SimpleAgent

program = SimpleAgent.route_executable!("jido.ai.request")

IO.puts("Agent route: jido.ai.request -> #{inspect(program)} -> jido.ai.response")

for flow <- [
      program,
      ReAct.ModelRound,
      ReAct.ToolReview
    ] do
  IO.puts("Graph: #{inspect(flow)}")

  flow.flow().components
  |> Enum.sort_by(&elem(&1, 0))
  |> Enum.each(fn {name, component} -> IO.puts("  #{name}: #{component.kind}") end)
end

tool_input = %{
  turn: %{
    model_outcome: %{
      tool_calls: [
        %{id: "add-1", name: "add", arguments: %{"left" => 2, "right" => 3}},
        %{
          id: "multiply-1",
          name: "multiply",
          arguments: %{"left" => 4, "right" => 5}
        }
      ]
    }
  }
}

{:continue, ^tool_input, tool_flow} =
  Actions.ExpandNext.run(%{kind: :tools, input: tool_input}, %{})

IO.puts("Graph: runtime Parallel tool calls")

tool_flow.components
|> Enum.sort_by(&elem(&1, 0))
|> Enum.each(fn
  {name, %{kind: :parallel, actions: actions}} ->
    IO.puts("  #{name}: parallel")

    Enum.each(actions, fn action ->
      IO.puts("    #{action.name}: #{inspect(action.call.target)}")
    end)

  {name, component} ->
    IO.puts("  #{name}: #{component.kind}")
end)

{:ok, preflight} =
  SimpleAgent.preflight(%{
    input: "Use add for 2 plus 3 and multiply for 4 times 5."
  })

IO.inspect(Enum.map(preflight.tools, & &1.name()), label: "Prepared tools")

Code.require_file("../../support/offline_inference_client.ex", __DIR__)
Code.require_file("react_offline_client.ex", __DIR__)
Code.require_file("simple_agent.ex", __DIR__)

alias Jido.AI.Reasoning.ReAct
alias Jido.Examples.AI.{ReActOfflineClient, SimpleAgent}

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

{:ok, preflight} =
  SimpleAgent.preflight(%{
    input: "Use add for 2 plus 3 and multiply for 4 times 5."
  })

IO.inspect(Enum.map(preflight.tools, & &1.name()), label: "Prepared tools")

agent = SimpleAgent.instantiate!(id: "simple-ai-runner")
request = SimpleAgent.request_signal!(%{input: "Use both tools."})

{:ok, _candidate, [%Jido.Agent.Directive.Reply{signal: reply}]} =
  SimpleAgent.cmd(agent, request, context: %{jido_ai_inference_client: ReActOfflineClient})

IO.inspect(
  Map.take(reply.data, [:output, :status, :model_calls, :tool_calls, :tool_rounds]),
  label: "Reply"
)

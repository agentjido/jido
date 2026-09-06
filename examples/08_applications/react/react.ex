defmodule Jido.Examples.Applications.React.FakeLLM do
  use Jido.Action, name: "pressure_react_fake_llm"

  @impl Jido.Action
  def run(%{script: [next | rest], messages: messages, test: test}, context) do
    send(test, {:react_stage, {:llm, next}})
    send(test, {:react_messages, messages})
    if context[:before_model], do: context.before_model.(messages)

    case next do
      {:tool, tool} ->
        {:ok,
         %{
           type: :tool_call,
           call: tool,
           script: rest,
           messages: messages,
           test: test
         }}

      {:answer, answer} ->
        {:ok,
         %{
           type: :answer,
           answer: answer,
           script: rest,
           messages: messages,
           test: test
         }}

      {:error, reason} ->
        {:error, Jido.Action.Error.execution_error("model failed", reason: reason)}
    end
  end
end

defmodule Jido.Examples.Applications.React.RouteResponse do
  use Jido.Action, name: "pressure_react_route_response"

  @impl Jido.Action
  def run(%{type: :tool_call} = input, _context) do
    {:continue, input, Jido.Examples.Applications.React.RunTool}
  end

  def run(%{type: :answer} = input, _context) do
    {:continue, input, Jido.Examples.Applications.React.CommitConversation}
  end
end

defmodule Jido.Examples.Applications.React.RunTool do
  use Jido.Action, name: "pressure_react_run_tool"

  @impl Jido.Action
  def run(%{call: tool, messages: messages, script: script, test: test}, _context) do
    send(test, {:react_stage, {:tool, tool}})

    next_messages =
      messages ++ [%{role: :tool, name: tool, content: "tool result"}]

    {:continue, %{messages: next_messages, script: script, test: test},
     Jido.Examples.Applications.React.ReasonFlow}
  end
end

defmodule Jido.Examples.Applications.React.CommitConversation do
  use Jido.Action, name: "pressure_react_commit_conversation"

  alias Jido.Plugin.Scheduler
  alias Jido.Signal

  @impl Jido.Action
  def run(%{answer: answer, messages: messages, test: test}, context) do
    send(test, {:react_stage, :commit})

    follow_up =
      Signal.new!("react.follow_up", %{answer: answer}, source: "/react/commit")

    next_state = %{
      context.agent_state
      | answers: context.agent_state.answers ++ [answer],
        messages:
          messages ++
            [%{role: :assistant, content: answer, messages_seen: length(messages)}]
    }

    {:ok, next_state, [Scheduler.schedule(10, follow_up)]}
  end
end

defmodule Jido.Examples.Applications.React.RecordFollowUp do
  use Jido.Action, name: "pressure_react_record_follow_up"

  @impl Jido.Action
  def run(_params, context) do
    {:ok, %{context.agent_state | followups: context.agent_state.followups + 1}}
  end
end

defmodule Jido.Examples.Applications.React.ReasonFlow do
  use Jido.Flow, name: "pressure_react_reason_flow"

  flow do
    dispatch "llm",
      decision: Jido.Examples.Applications.React.FakeLLM,
      expander: Jido.Examples.Applications.React.RouteResponse,
      params: %{
        messages: input(:messages),
        script: input(:script),
        test: input(:test)
      }

    output result("llm")
  end
end

defmodule Jido.Examples.Applications.React.BeginConversation do
  use Jido.Action, name: "pressure_react_begin_conversation"

  @impl Jido.Action
  def run(input, %{agent_state: state}) do
    {:continue, %{input | messages: state.messages ++ input.messages},
     Jido.Examples.Applications.React.ReasonFlow}
  end
end

defmodule Jido.Examples.Applications.React.Agent do
  use Jido.Agent, name: "pressure_react_agent"

  agent do
    schema Zoi.object(%{
             answers: Zoi.list(Zoi.string()) |> Zoi.default([]),
             messages: Zoi.list(Zoi.map()) |> Zoi.default([]),
             followups: Zoi.integer() |> Zoi.default(0)
           })

    plugin Jido.Plugin.Scheduler
  end

  routes do
    route "react.reason", Jido.Examples.Applications.React.BeginConversation
    route "react.follow_up", Jido.Examples.Applications.React.RecordFollowUp
  end
end

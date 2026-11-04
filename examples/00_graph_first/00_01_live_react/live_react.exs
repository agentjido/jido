defmodule Jido.Examples.GraphFirst.Add do
  use Jido.Action,
    id: "jido/examples/graph-first/tools/add",
    name: "add",
    description: "Add two numbers.",
    schema: Jido.Joi.object(%{left: Jido.Joi.number(), right: Jido.Joi.number()}),
    output_schema: Jido.Joi.object(%{value: Jido.Joi.number()})

  @impl Jido.Action
  def run(%{left: left, right: right}, _context), do: {:ok, %{value: left + right}}
end

defmodule Jido.Examples.GraphFirst.Multiply do
  use Jido.Action,
    id: "jido/examples/graph-first/tools/multiply",
    name: "multiply",
    description: "Multiply two numbers.",
    schema: Jido.Joi.object(%{left: Jido.Joi.number(), right: Jido.Joi.number()}),
    output_schema: Jido.Joi.object(%{value: Jido.Joi.number()})

  @impl Jido.Action
  def run(%{left: left, right: right}, _context), do: {:ok, %{value: left * right}}
end

defmodule Jido.Examples.GraphFirst.Agent do
  use Jido.AI.Agent,
    id: "jido/examples/graph-first/agent",
    vsn: 1,
    name: "graph_first_live_agent",
    description: "Run the canonical ReAct graph through a live Jido AgentServer"

  ai do
    reasoning Jido.AI.Reasoning.ReAct do
      instructions "Use every requested arithmetic tool. Report only results returned by tools."

      limits do
        model_calls 4
        tool_rounds 2
        tool_calls 4
        retries 1
        elapsed_ms(120_000)
      end
    end

    tools do
      action Jido.Examples.GraphFirst.Add
      action Jido.Examples.GraphFirst.Multiply
    end
  end
end

alias Jido.Agent.Directive.Reply
alias Jido.AgentServer
alias Jido.Examples.GraphFirst.Agent

model = System.get_env("JIDO_LIVE_MODEL", "openai:gpt-4o-mini")

prompt =
  System.get_env(
    "JIDO_LIVE_PROMPT",
    "In one tool round, use add for 2 plus 3 and multiply for 4 times 5. Then report both tool results."
  )

{:ok, _jido} = Jido.start(namespace: "jido/examples/graph-first")

{:ok, server} =
  Jido.start_agent(Jido.Default, Agent,
    id: "graph-first-live-agent",
    turn_timeout: :infinity
  )

:ok = AgentServer.await_ready(server)

request =
  Agent.request_signal!(%{
    input: prompt,
    model: model,
    options: %{
      max_tokens: 256,
      receive_timeout: 60_000,
      temperature: 0.0
    }
  })

result = AgentServer.call(server, request, timeout: :infinity, admission_timeout: :infinity)

case result do
  {:ok, committed, [%Reply{signal: response}]} ->
    data = response.data

    safe_summary =
      Map.take(data, [
        :status,
        :reason_code,
        :reason,
        :model_calls,
        :tool_rounds,
        :tool_calls,
        :tool_errors,
        :retries,
        :budget,
        :usage
      ])

    unless data.status == :completed,
      do: raise("ReAct did not complete: #{inspect(safe_summary)}")

    unless data.model_calls == 2,
      do: raise("Expected two model calls, got #{inspect(data.model_calls)}")

    unless data.tool_rounds == 1,
      do: raise("Expected one parallel tool round, got #{inspect(data.tool_rounds)}")

    unless data.tool_calls == 2,
      do: raise("Expected two tool calls, got #{inspect(data.tool_calls)}")

    unless match?(%Jido.Session{}, committed.state.session),
      do: raise("The AgentServer did not commit the Session")

    IO.inspect(
      %{
        model: model,
        status: data.status,
        output: data.output,
        model_calls: data.model_calls,
        tool_rounds: data.tool_rounds,
        tool_calls: data.tool_calls,
        session_id: committed.state.session.id,
        thread_rev: committed.state.session.thread.rev
      },
      label: "Live ReAct result"
    )

  other ->
    raise("Live ReAct AgentServer call failed: #{inspect(other)}")
end

defmodule Jido.Examples.ReActAgent do
  @moduledoc """
  An Agent that runs one effectful ReAct Flow for each input Signal.

  The Flow calls a model process and a tool process. These calls are external
  effects. They occur during the Flow because their results control the next
  Flow step. The Agent Server commits the final conversation once after the
  complete Flow returns.

  `ScriptedModel` and `SearchTool` keep the example local and deterministic.
  A real application can supply other modules that implement the same small
  client contracts.
  """

  use Jido.Agent,
    name: "examples_react_agent",
    description: "Runs one effectful ReAct Flow for each input Signal"

  agent do
    schema Zoi.object(%{
             messages: Zoi.list(Zoi.map()) |> Zoi.default([]),
             last_answer: Zoi.string() |> Zoi.default(""),
             turns: Zoi.integer() |> Zoi.min(0) |> Zoi.default(0)
           })
  end

  routes do
    route "examples.react.ask", Jido.Examples.ReActAgent.ReasonFlow
  end

  alias Jido.AgentServer, as: Server
  alias Jido.Signal

  @default_max_steps 8

  @typedoc "A model client module and its client reference."
  @type model_client :: {module(), term()}

  @typedoc "Tool clients indexed by the name returned by the model."
  @type tool_clients :: %{required(String.t()) => {module(), term()}}

  @doc "Runs one model and tool Turn. Options set the step limit and caller timeout."
  @spec ask(Server.server(), String.t(), model_client(), tool_clients(), keyword()) ::
          Server.signal_result()
  def ask(server, prompt, model, tools, opts \\ [])
      when is_binary(prompt) and is_tuple(model) and is_map(tools) do
    max_steps = Keyword.get(opts, :max_steps, @default_max_steps)

    Server.call(server, ask_signal!(prompt, max_steps),
      context: %{model: model, tools: tools},
      timeout: Keyword.get(opts, :timeout, 5_000)
    )
  end

  @doc "Builds a Signal that starts one complete ReAct Turn."
  @spec ask_signal!(String.t(), pos_integer()) :: Signal.t()
  def ask_signal!(prompt, max_steps \\ @default_max_steps)
      when is_binary(prompt) and is_integer(max_steps) and
             max_steps > 0 do
    Signal.new!(
      "examples.react.ask",
      %{
        prompt: prompt,
        messages: [],
        new_turn?: true,
        max_steps: max_steps,
        steps_remaining: max_steps
      },
      source: "/examples/react"
    )
  end
end

defmodule Jido.Examples.ReActAgent.Model do
  @moduledoc "The client contract used by the effectful model Action."

  @type decision :: {:tool, String.t(), term()} | {:answer, String.t()}

  @callback complete(client :: term(), messages :: [map()]) ::
              {:ok, decision()} | {:error, term()}
end

defmodule Jido.Examples.ReActAgent.Tool do
  @moduledoc "The client contract used by the effectful tool Action."

  @callback run(client :: term(), input :: term()) :: {:ok, term()} | {:error, term()}
end

defmodule Jido.Examples.ReActAgent.ScriptedModel do
  @moduledoc "A model process that returns a fixed sequence of decisions."

  use GenServer

  @behaviour Jido.Examples.ReActAgent.Model

  @type decision :: Jido.Examples.ReActAgent.Model.decision()
  @type response :: decision() | {:error, term()}

  @spec start_link([response()]) :: GenServer.on_start()
  def start_link(responses) when is_list(responses) do
    GenServer.start_link(__MODULE__, responses)
  end

  @impl Jido.Examples.ReActAgent.Model
  def complete(server, messages) when is_list(messages) do
    GenServer.call(server, {:complete, messages})
  end

  @doc "Returns the message list received by each model call."
  @spec calls(GenServer.server()) :: [[map()]]
  def calls(server), do: GenServer.call(server, :calls)

  @impl GenServer
  def init(responses), do: {:ok, %{responses: responses, calls: []}}

  @impl GenServer
  def handle_call({:complete, messages}, _from, %{responses: [{:error, reason} | rest]} = state) do
    next_state = %{state | responses: rest, calls: [messages | state.calls]}
    {:reply, {:error, reason}, next_state}
  end

  def handle_call({:complete, messages}, _from, %{responses: [next | rest]} = state) do
    next_state = %{state | responses: rest, calls: [messages | state.calls]}
    {:reply, {:ok, next}, next_state}
  end

  def handle_call({:complete, messages}, _from, %{responses: []} = state) do
    next_state = %{state | calls: [messages | state.calls]}
    {:reply, {:error, :model_script_exhausted}, next_state}
  end

  def handle_call(:calls, _from, state) do
    {:reply, Enum.reverse(state.calls), state}
  end
end

defmodule Jido.Examples.ReActAgent.SearchTool do
  @moduledoc "A process-backed search tool with a fixed local index."

  use GenServer

  @behaviour Jido.Examples.ReActAgent.Tool

  @spec start_link(map()) :: GenServer.on_start()
  def start_link(index) when is_map(index), do: GenServer.start_link(__MODULE__, index)

  @impl Jido.Examples.ReActAgent.Tool
  def run(server, query), do: GenServer.call(server, {:search, query})

  @doc "Returns all search queries in call order."
  @spec queries(GenServer.server()) :: [term()]
  def queries(server), do: GenServer.call(server, :queries)

  @impl GenServer
  def init(index), do: {:ok, %{index: index, queries: []}}

  @impl GenServer
  def handle_call({:search, query}, _from, state) do
    response = Map.get(state.index, query, "No result for #{inspect(query)}")

    reply =
      case response do
        {:ok, result} -> {:ok, result}
        {:error, reason} -> {:error, reason}
        result -> {:ok, result}
      end

    {:reply, reply, %{state | queries: [query | state.queries]}}
  end

  def handle_call(:queries, _from, state) do
    {:reply, Enum.reverse(state.queries), state}
  end
end

defmodule Jido.Examples.ReActAgent.BlockingModel do
  @moduledoc "A controllable model used to test cancellation without a live provider."

  @behaviour Jido.Examples.ReActAgent.Model

  @impl Jido.Examples.ReActAgent.Model
  def complete({owner, token}, messages) when is_pid(owner) do
    send(owner, {:react_model_waiting, self(), token, messages})

    receive do
      {:release_react_model, ^token} -> {:ok, {:answer, "released"}}
    end
  end
end

defmodule Jido.Examples.ReActAgent.CallModel do
  @moduledoc false

  use Jido.Action, name: "examples_react_call_model"

  alias Jido.Action.Error

  @impl Jido.Action
  def run(%{steps_remaining: 0, max_steps: max_steps}, _context) do
    {:error,
     Error.validation_error("ReAct model step limit reached", %{
       max_steps: max_steps
     })}
  end

  def run(input, %{agent_state: agent_state} = context) do
    messages = turn_messages(input, agent_state)
    {module, client} = context.model
    steps_remaining = input.steps_remaining - 1

    case module.complete(client, messages) do
      {:ok, {:tool, name, tool_input}} when is_binary(name) ->
        {:ok,
         %{
           kind: :tool,
           tool_name: name,
           tool_input: tool_input,
           messages: messages,
           max_steps: input.max_steps,
           steps_remaining: steps_remaining
         }}

      {:ok, {:answer, answer}} when is_binary(answer) and byte_size(answer) > 0 ->
        {:ok,
         %{
           kind: :answer,
           answer: answer,
           messages: messages,
           max_steps: input.max_steps,
           steps_remaining: steps_remaining
         }}

      {:error, reason} ->
        {:error, reason}

      result ->
        {:error, {:invalid_model_result, result}}
    end
  end

  defp turn_messages(%{new_turn?: true, prompt: prompt}, agent_state) do
    agent_state.messages ++ [%{role: :user, content: prompt}]
  end

  defp turn_messages(%{new_turn?: false, messages: messages}, _agent_state), do: messages
end

defmodule Jido.Examples.ReActAgent.RouteModelDecision do
  @moduledoc false

  use Jido.Action, name: "examples_react_route_model_decision"

  @impl Jido.Action
  def run(%{kind: :tool} = input, _context) do
    {:continue, input, Jido.Examples.ReActAgent.RunTool}
  end

  def run(%{kind: :answer} = input, _context) do
    {:continue, input, Jido.Examples.ReActAgent.CommitAnswer}
  end
end

defmodule Jido.Examples.ReActAgent.RunTool do
  @moduledoc false

  use Jido.Action, name: "examples_react_run_tool"

  @impl Jido.Action
  def run(input, context) do
    with {:ok, {module, client}} <- Map.fetch(context.tools, input.tool_name),
         {:ok, result} <- module.run(client, input.tool_input) do
      messages =
        input.messages ++
          [
            %{
              role: :assistant,
              tool_call: %{name: input.tool_name, input: input.tool_input}
            },
            %{role: :tool, name: input.tool_name, content: result}
          ]

      {:continue,
       %{
         prompt: nil,
         messages: messages,
         new_turn?: false,
         max_steps: input.max_steps,
         steps_remaining: input.steps_remaining
       }, Jido.Examples.ReActAgent.ReasonFlow}
    else
      :error -> {:error, {:unknown_tool, input.tool_name}}
      {:error, reason} -> {:error, reason}
    end
  end
end

defmodule Jido.Examples.ReActAgent.CommitAnswer do
  @moduledoc false

  use Jido.Action, name: "examples_react_commit_answer"

  @impl Jido.Action
  def run(%{answer: answer, messages: messages}, %{agent_state: agent_state}) do
    {:ok,
     %{
       agent_state
       | messages: messages ++ [%{role: :assistant, content: answer}],
         last_answer: answer,
         turns: agent_state.turns + 1
     }}
  end
end

defmodule Jido.Examples.ReActAgent.ReasonFlow do
  @moduledoc "Runs model and tool continuations until the model returns an answer."

  use Jido.Flow,
    name: "examples_react_reason",
    schema:
      Zoi.object(%{
        prompt: Zoi.union([Zoi.string(), Zoi.literal(nil)]),
        messages: Zoi.list(Zoi.map()),
        new_turn?: Zoi.boolean(),
        max_steps: Zoi.integer() |> Zoi.min(1),
        steps_remaining: Zoi.integer() |> Zoi.min(0)
      })

  flow do
    dispatch "reason",
      decision: Jido.Examples.ReActAgent.CallModel,
      expander: Jido.Examples.ReActAgent.RouteModelDecision,
      params: %{
        prompt: input(:prompt),
        messages: input(:messages),
        new_turn?: input(:new_turn?),
        max_steps: input(:max_steps),
        steps_remaining: input(:steps_remaining)
      }

    output result("reason")
  end
end

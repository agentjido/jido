defmodule Jido.Examples.ReActAgent.ScriptedModel do
  @moduledoc "A local model adapter that returns a fixed sequence of decisions."

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
  @moduledoc "A local search adapter with a fixed in-memory index."

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

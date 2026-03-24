defmodule Jido.Thread.Agent do
  @moduledoc """
  Helper for managing Thread in agent state.

  Thread is stored at the reserved key `:__thread__` in `agent.state`.
  This follows the same pattern as `:__strategy__` for strategy state.

  ## Example

      alias Jido.Thread.Agent, as: ThreadAgent

      # Ensure agent has a thread
      agent = ThreadAgent.ensure(agent, metadata: %{user_id: "u1"})

      # Append an entry
      agent = ThreadAgent.append(agent, %{kind: :message, payload: %{text: "hi"}})

      # Get the thread
      thread = ThreadAgent.get(agent)
  """

  alias Jido.Agent
  alias Jido.Thread

  @key :__thread__

  @doc "Returns the reserved key for thread storage"
  @spec key() :: atom()
  def key, do: @key

  @doc "Get thread from agent state"
  @spec get(Agent.t(), Thread.t() | nil) :: Thread.t() | nil
  def get(%Agent{state: state}, default \\ nil) do
    Map.get(state, @key, default)
  end

  @doc "Put thread into agent state"
  @spec put(Agent.t(), Thread.t()) :: Agent.t()
  def put(%Agent{} = agent, %Thread{} = thread) do
    %{agent | state: Map.put(agent.state, @key, thread)}
  end

  @doc "Update thread using a function"
  @spec update(Agent.t(), (Thread.t() | nil -> Thread.t())) :: Agent.t()
  def update(%Agent{} = agent, fun) when is_function(fun, 1) do
    current = get(agent)
    put(agent, fun.(current))
  end

  @doc "Ensure agent has a thread (initialize if missing)"
  @spec ensure(Agent.t(), keyword()) :: Agent.t()
  def ensure(%Agent{} = agent, opts \\ []) do
    case get(agent) do
      nil -> put(agent, Thread.new(opts))
      _thread -> agent
    end
  end

  @doc "Append entry to agent's thread (ensures thread exists)"
  @spec append(Agent.t(), term(), keyword()) :: Agent.t()
  def append(%Agent{} = agent, entry_or_entries, opts \\ []) do
    agent = ensure(agent, opts)
    thread = get(agent)
    put(agent, Thread.append(thread, entry_or_entries))
  end

  @doc "Check if agent has a thread"
  @spec has_thread?(Agent.t()) :: boolean()
  def has_thread?(%Agent{} = agent), do: get(agent) != nil
end

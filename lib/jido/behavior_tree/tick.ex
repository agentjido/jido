defmodule Jido.BehaviorTree.Tick do
  @moduledoc """
  Represents a single execution cycle (tick) of a behavior tree.

  A tick contains the context needed for a single traversal of the behavior tree,
  including the shared blackboard, timing information, and a sequence number
  for tracking execution order.

  Ticks are immutable and are passed down through the tree during execution,
  allowing nodes to access shared state and timing information.
  """

  alias Jido.BehaviorTree.Blackboard

  @schema Zoi.struct(
            __MODULE__,
            %{
              blackboard: Zoi.any(description: "The shared blackboard for the tick"),
              timestamp: Zoi.any(description: "The timestamp when the tick was created"),
              sequence:
                Zoi.integer(description: "The sequence number of the tick")
                |> Zoi.min(0)
                |> Zoi.default(0),
              agent:
                Zoi.any(description: "The Jido agent (for Agent integration)")
                |> Zoi.optional(),
              directives:
                Zoi.list(Zoi.any(description: "Accumulated directives"))
                |> Zoi.default([]),
              context:
                Zoi.any(description: "Execution context for the tree")
                |> Zoi.default(%{})
            },
            coerce: true
          )

  @typedoc "A single execution cycle of a behavior tree"
  @type t :: unquote(Zoi.type_spec(@schema))

  @enforce_keys Zoi.Struct.enforce_keys(@schema)
  defstruct Zoi.Struct.struct_fields(@schema)

  @doc "Returns the Zoi schema for this module"
  def schema, do: @schema

  @doc """
  Creates a new tick with the given blackboard.

  The timestamp is set to the current time and sequence starts at 0.

  ## Examples

      iex> bb = Jido.BehaviorTree.Blackboard.new(%{user_id: 123})
      iex> tick = Jido.BehaviorTree.Tick.new(bb)
      %Jido.BehaviorTree.Tick{blackboard: bb, sequence: 0}

  """
  @spec new(Blackboard.t()) :: t()
  def new(blackboard \\ Blackboard.new()) do
    %__MODULE__{
      blackboard: blackboard,
      timestamp: DateTime.utc_now(),
      sequence: 0
    }
  end

  @doc """
  Creates a new tick with explicit parameters.

  ## Examples

      iex> bb = Jido.BehaviorTree.Blackboard.new()
      iex> now = DateTime.utc_now()
      iex> tick = Jido.BehaviorTree.Tick.new(bb, now, 5)
      %Jido.BehaviorTree.Tick{blackboard: bb, timestamp: now, sequence: 5}

  """
  @spec new(Blackboard.t(), DateTime.t(), non_neg_integer()) :: t()
  def new(blackboard, timestamp, sequence) do
    %__MODULE__{
      blackboard: blackboard,
      timestamp: timestamp,
      sequence: sequence,
      agent: nil,
      directives: [],
      context: %{}
    }
  end

  @doc """
  Creates a new tick with Jido agent context for Agent integration.

  This constructor is used by `Jido.Plugin.BehaviorTree` to pass
  agent state and execution context through the tree during traversal.

  ## Parameters

  - `blackboard` - The shared blackboard
  - `agent` - The current Jido agent struct
  - `directives` - Initial list of directives (usually empty)
  - `context` - Tree execution context

  ## Examples

      tick = Tick.new_with_context(blackboard, agent, [], %{agent_id: agent.id})

  """
  @spec new_with_context(Blackboard.t(), term(), list(), map()) :: t()
  def new_with_context(blackboard, agent, directives \\ [], context \\ %{}) do
    %__MODULE__{
      blackboard: blackboard,
      timestamp: DateTime.utc_now(),
      sequence: 0,
      agent: agent,
      directives: directives,
      context: context
    }
  end

  @doc """
  Updates the blackboard in the tick.

  ## Examples

      iex> tick = Jido.BehaviorTree.Tick.new()
      iex> new_bb = Jido.BehaviorTree.Blackboard.put(tick.blackboard, :result, "success")
      iex> updated_tick = Jido.BehaviorTree.Tick.update_blackboard(tick, new_bb)
      iex> Jido.BehaviorTree.Blackboard.get(updated_tick.blackboard, :result)
      "success"

  """
  @spec update_blackboard(t(), Blackboard.t()) :: t()
  def update_blackboard(%__MODULE__{} = tick, blackboard) do
    %{tick | blackboard: blackboard}
  end

  @doc """
  Increments the sequence number in the tick.

  ## Examples

      iex> tick = Jido.BehaviorTree.Tick.new()
      iex> updated_tick = Jido.BehaviorTree.Tick.increment_sequence(tick)
      iex> updated_tick.sequence
      1

  """
  @spec increment_sequence(t()) :: t()
  def increment_sequence(%__MODULE__{sequence: seq} = tick) do
    %{tick | sequence: seq + 1}
  end

  @doc """
  Gets a value from the tick's blackboard.

  ## Examples

      iex> bb = Jido.BehaviorTree.Blackboard.new(%{user_id: 123})
      iex> tick = Jido.BehaviorTree.Tick.new(bb)
      iex> Jido.BehaviorTree.Tick.get(tick, :user_id)
      123

  """
  @spec get(t(), term(), term()) :: term()
  def get(%__MODULE__{blackboard: bb}, key, default \\ nil) do
    Blackboard.get(bb, key, default)
  end

  @doc """
  Sets a value in the tick's blackboard, returning an updated tick.

  ## Examples

      iex> tick = Jido.BehaviorTree.Tick.new()
      iex> updated_tick = Jido.BehaviorTree.Tick.put(tick, :result, "success")
      iex> Jido.BehaviorTree.Tick.get(updated_tick, :result)
      "success"

  """
  @spec put(t(), term(), term()) :: t()
  def put(%__MODULE__{blackboard: bb} = tick, key, value) do
    updated_bb = Blackboard.put(bb, key, value)
    %{tick | blackboard: updated_bb}
  end

  @doc """
  Updates a value in the tick's blackboard using a function.

  ## Examples

      iex> bb = Jido.BehaviorTree.Blackboard.new(%{counter: 5})
      iex> tick = Jido.BehaviorTree.Tick.new(bb)
      iex> updated_tick = Jido.BehaviorTree.Tick.update(tick, :counter, 0, &(&1 + 1))
      iex> Jido.BehaviorTree.Tick.get(updated_tick, :counter)
      6

  """
  @spec update(t(), term(), term(), (term() -> term())) :: t()
  def update(%__MODULE__{blackboard: bb} = tick, key, initial, fun) do
    updated_bb = Blackboard.update(bb, key, initial, fun)
    %{tick | blackboard: updated_bb}
  end

  @doc """
  Gets the elapsed time since the tick was created.

  ## Examples

      iex> tick = Jido.BehaviorTree.Tick.new()
      iex> Process.sleep(10)
      iex> elapsed = Jido.BehaviorTree.Tick.elapsed_time(tick)
      iex> elapsed > 0
      true

  """
  @spec elapsed_time(t()) :: integer()
  def elapsed_time(%__MODULE__{timestamp: timestamp}) do
    DateTime.diff(DateTime.utc_now(), timestamp, :millisecond)
  end

  @doc """
  Checks if the tick has exceeded a timeout.

  ## Examples

      iex> tick = Jido.BehaviorTree.Tick.new()
      iex> Jido.BehaviorTree.Tick.timed_out?(tick, 1000)
      false

  """
  @spec timed_out?(t(), non_neg_integer()) :: boolean()
  def timed_out?(tick, timeout_ms) do
    elapsed_time(tick) > timeout_ms
  end

  @doc """
  Updates the agent in the tick.

  Used by Action nodes to update agent state after executing Jido actions.
  """
  @spec update_agent(t(), term()) :: t()
  def update_agent(%__MODULE__{} = tick, agent) do
    %{tick | agent: agent}
  end

  @doc """
  Appends directives to the tick's directive list.

  Used by Action nodes to accumulate directives from Jido Effects.
  """
  @spec append_directives(t(), list()) :: t()
  def append_directives(%__MODULE__{directives: existing} = tick, new_directives) do
    %{tick | directives: existing ++ List.wrap(new_directives)}
  end

  @doc """
  Updates both agent and appends directives in one call.

  Convenience function for Action nodes applying Jido Effects.
  """
  @spec apply_agent_update(t(), term(), list()) :: t()
  def apply_agent_update(%__MODULE__{} = tick, agent, directives) do
    tick
    |> update_agent(agent)
    |> append_directives(directives)
  end
end

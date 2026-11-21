defmodule Jido.BehaviorTree.Nodes.Repeat do
  @moduledoc """
  A decorator node that repeats its child a specified number of times.

  The node ticks the child repeatedly until:
  - The child has succeeded `count` times (returns `:success`)
  - The child fails (returns `:failure` immediately)
  - The child returns `:running` (returns `:running`)

  ## Example

      repeat = Repeat.new(attack_action, 3)
      # Executes attack_action 3 times before succeeding

  """

  alias Jido.BehaviorTree.Node

  @schema Zoi.struct(
            __MODULE__,
            %{
              child: Zoi.any(description: "The child node to repeat"),
              count: Zoi.integer(description: "Number of times to repeat") |> Zoi.min(1),
              current_iteration: Zoi.integer(description: "Current iteration") |> Zoi.min(0) |> Zoi.default(0)
            },
            coerce: true
          )

  @type t :: unquote(Zoi.type_spec(@schema))

  @enforce_keys Zoi.Struct.enforce_keys(@schema)
  defstruct Zoi.Struct.struct_fields(@schema)

  @doc "Returns the Zoi schema for this module"
  def schema, do: @schema

  @behaviour Jido.BehaviorTree.Node

  @doc """
  Creates a new Repeat node that repeats the child `count` times.

  ## Examples

      iex> Repeat.new(child_node, 5)
      %Repeat{child: child_node, count: 5, current_iteration: 0}

  """
  @spec new(Node.t(), pos_integer()) :: t()
  def new(child, count) when is_integer(count) and count >= 1 do
    %__MODULE__{child: child, count: count, current_iteration: 0}
  end

  @impl true
  def tick(state, tick) do
    {status, state, _tick} = tick_with_context(state, tick)
    {status, state}
  end

  @doc """
  Context-aware tick that preserves child tick mutations.
  """
  @impl true
  @spec tick_with_context(t(), Jido.BehaviorTree.Tick.t()) ::
          {Jido.BehaviorTree.Status.t(), t(), Jido.BehaviorTree.Tick.t()}
  def tick_with_context(%__MODULE__{child: child, count: count, current_iteration: iteration} = state, tick) do
    {status, updated_child, updated_tick} = Node.execute_tick_with_context(child, tick)

    case status do
      :success ->
        new_iteration = iteration + 1

        if new_iteration >= count do
          {:success, %{state | child: updated_child, current_iteration: 0}, updated_tick}
        else
          halted_child = Node.execute_halt(updated_child)
          {:running, %{state | child: halted_child, current_iteration: new_iteration}, updated_tick}
        end

      :failure ->
        {:failure, %{state | child: updated_child, current_iteration: 0}, updated_tick}

      :running ->
        {:running, %{state | child: updated_child}, updated_tick}

      {:error, _} = error ->
        {error, %{state | child: updated_child, current_iteration: 0}, updated_tick}
    end
  end

  @impl true
  def halt(%__MODULE__{child: child} = state) do
    halted_child = Node.execute_halt(child)
    %{state | child: halted_child, current_iteration: 0}
  end
end

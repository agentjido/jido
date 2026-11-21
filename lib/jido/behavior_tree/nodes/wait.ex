defmodule Jido.BehaviorTree.Nodes.Wait do
  @moduledoc """
  A leaf node that waits for a specified duration.

  Returns `:running` until the duration has elapsed, then returns `:success`.

  ## Example

      wait = Wait.new(1000)  # Wait 1 second
      # Returns :running until 1000ms has passed

  """

  @schema Zoi.struct(
            __MODULE__,
            %{
              duration_ms: Zoi.integer(description: "Duration to wait in milliseconds") |> Zoi.min(0),
              start_time: Zoi.any(description: "Start time of the wait") |> Zoi.optional()
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
  Creates a new Wait node with the specified duration.

  ## Examples

      iex> Wait.new(1000)
      %Wait{duration_ms: 1000, start_time: nil}

  """
  @spec new(non_neg_integer()) :: t()
  def new(duration_ms) when is_integer(duration_ms) and duration_ms >= 0 do
    %__MODULE__{duration_ms: duration_ms, start_time: nil}
  end

  @impl true
  def tick(%__MODULE__{start_time: nil} = state, _tick) do
    {:running, %{state | start_time: System.monotonic_time(:millisecond)}}
  end

  def tick(%__MODULE__{duration_ms: duration, start_time: start} = state, _tick) do
    elapsed = System.monotonic_time(:millisecond) - start

    if elapsed >= duration do
      {:success, %{state | start_time: nil}}
    else
      {:running, state}
    end
  end

  @impl true
  def halt(state) do
    %{state | start_time: nil}
  end
end

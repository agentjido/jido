defmodule Jido.AgentServer.AdmissionDeadline do
  @moduledoc false

  @type t :: :infinity | {node(), integer()}

  @spec new(timeout()) :: t()
  def new(:infinity), do: :infinity

  def new(timeout) when is_integer(timeout) and timeout >= 0 do
    new(timeout, node(), fn -> System.monotonic_time(:millisecond) end)
  end

  @doc false
  def new(timeout, origin, now) when is_integer(timeout) and timeout >= 0 do
    {origin, now.() + timeout}
  end

  @spec expired?(t()) :: boolean()
  def expired?(:infinity), do: false

  def expired?(deadline) do
    expired?(
      deadline,
      node(),
      fn -> System.monotonic_time(:millisecond) end,
      fn origin -> :erpc.call(origin, System, :monotonic_time, [:millisecond], 1_000) end
    )
  catch
    _kind, _reason -> true
  end

  @doc false
  def expired?({origin, deadline}, current_node, local_now, origin_now) do
    if origin == current_node do
      local_now.() >= deadline
    else
      started = local_now.()
      now = origin_now.(origin)
      elapsed = local_now.() - started
      now + elapsed >= deadline
    end
  end
end

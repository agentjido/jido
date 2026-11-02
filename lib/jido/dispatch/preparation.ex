defmodule Jido.Dispatch.Preparation do
  @moduledoc false

  alias Jido.Signal
  alias Jido.Tracing.Context, as: TraceContext

  @spec propagate(Signal.t(), Signal.t()) :: Signal.t()
  def propagate(%Signal{} = signal, %Signal{} = source) do
    case TraceContext.propagate_to(signal, source.id) do
      {:ok, traced} -> traced
      {:error, _reason} -> signal
    end
  end

  @spec inherit_bus_scope(term(), atom() | nil) :: term()
  def inherit_bus_scope({:bus, opts}, jido) when is_atom(jido) and not is_nil(jido) do
    {:bus, Keyword.put_new(opts, :jido, jido)}
  end

  def inherit_bus_scope(targets, jido) when is_list(targets),
    do: Enum.map(targets, &inherit_bus_scope(&1, jido))

  def inherit_bus_scope(target, _jido), do: target
end

defmodule JidoTest.Support.TestTracer do
  @moduledoc false
  @behaviour Jido.Observe.Tracer
  use Elixir.Agent

  def start_link(_opts \\ []), do: Elixir.Agent.start_link(fn -> [] end, name: __MODULE__)
  def get_spans, do: Elixir.Agent.get(__MODULE__, & &1)
  def clear, do: Elixir.Agent.update(__MODULE__, fn _ -> [] end)

  @impl true
  def span_start(event_prefix, metadata) do
    ref = make_ref()
    Elixir.Agent.update(__MODULE__, &[{:start, ref, event_prefix, metadata} | &1])
    ref
  end

  @impl true
  def span_stop(ref, measurements) do
    Elixir.Agent.update(__MODULE__, &[{:stop, ref, measurements} | &1])
    :ok
  end

  @impl true
  def span_exception(ref, kind, reason, stacktrace) do
    Elixir.Agent.update(__MODULE__, &[{:exception, ref, kind, reason, stacktrace} | &1])
    :ok
  end
end

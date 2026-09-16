defmodule Jido.Plugin.Scheduler.Server do
  @moduledoc "Owns timers, delivery, and readiness after Scheduler commits."
  use Jido.AgentServer.Plugin

  alias Jido.Plugin.{DirectiveContext, Init}
  alias Jido.Plugin.Scheduler
  alias Jido.Plugin.Scheduler.{Acknowledge, Durable, Queue, Runtime}

  @impl true
  def dispatch(runtime, %Queue{} = directive, %DirectiveContext{} = context, _opts) do
    if Durable.current_queue?(context.plugin_state, directive) do
      GenServer.cast(runtime, :pending_changed)
    else
      :ok
    end
  end

  def dispatch(runtime, %Acknowledge{}, _context, _opts),
    do: GenServer.cast(runtime, :pending_changed)

  def dispatch(runtime, directive, %DirectiveContext{} = context, opts) do
    GenServer.call(runtime, {:directive, directive, context}, Keyword.get(opts, :timeout, 5_000))
  catch
    :exit, reason -> {:error, {:scheduler_runtime_unavailable, reason}}
  end

  @impl true
  def await_ready(runtime, opts) do
    GenServer.call(runtime, :await_ready, Keyword.get(opts, :timeout, 5_000))
  catch
    :exit, reason -> {:error, {:scheduler_runtime_unavailable, reason}}
  end

  def child_spec(%Init{} = init) do
    Supervisor.child_spec({Runtime, init}, id: Scheduler)
  end
end

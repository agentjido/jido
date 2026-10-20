defmodule Jido.Plugin.Scheduler.Server do
  @moduledoc "Owns timers and readiness after Scheduler commits."
  @behaviour Jido.Plugin

  alias Jido.Plugin.{DirectiveContext, Init}
  alias Jido.Plugin.Scheduler
  alias Jido.Plugin.Scheduler.Runtime

  @impl true
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

  @impl true
  def child_spec(%Init{} = init) do
    Supervisor.child_spec({Runtime, init}, id: Scheduler)
  end
end

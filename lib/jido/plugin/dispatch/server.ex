defmodule Jido.Plugin.Dispatch.Server do
  @moduledoc "Runs post-commit Signal delivery through the Dispatch runtime."
  use Jido.AgentServer.Plugin

  alias Jido.Dispatch.Preparation, as: DispatchPreparation
  alias Jido.Plugin.{DirectiveContext, Init}
  alias Jido.Plugin.Dispatch
  alias Jido.Plugin.Dispatch.{Runtime, Send}

  @impl true
  def dispatch(runtime, %Send{} = directive, %DirectiveContext{} = context, opts) do
    signal = DispatchPreparation.propagate(directive.signal, context.effective_signal)
    target = DispatchPreparation.inherit_bus_scope(directive.target, context.jido)

    GenServer.call(runtime, {:deliver, signal, target}, Keyword.get(opts, :timeout, 5_000))
  catch
    :exit, reason -> {:error, {:dispatch_runtime_unavailable, reason}}
  end

  def child_spec(%Init{} = init) do
    Supervisor.child_spec({Runtime, init}, id: Dispatch)
  end
end

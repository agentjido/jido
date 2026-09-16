defmodule Jido.Plugin.SensorManager.Server do
  @moduledoc "Owns supervised sensor reconciliation after Agent commits."
  use Jido.AgentServer.Plugin

  alias Jido.Plugin.{DirectiveContext, Init}
  alias Jido.Plugin.SensorManager
  alias Jido.Plugin.SensorManager.Runtime

  @impl true
  def validate_options(opts) do
    delay = Keyword.get(opts, :retry_delay_ms, 1_000)

    if is_integer(delay) and delay in 1..4_294_967_295 do
      :ok
    else
      {:error,
       Jido.Error.validation_error("Sensor Manager retry delay is invalid",
         kind: :config,
         details: %{retry_delay_ms: delay}
       )}
    end
  end

  @impl true
  def dispatch(runtime, _directive, %DirectiveContext{} = context, opts) do
    timeout = Keyword.get(opts, :timeout, 5_000)
    Runtime.reconcile(runtime, context.plugin_state.desired, context.state_version, timeout)
  catch
    :exit, reason -> {:error, {:sensor_manager_runtime_unavailable, reason}}
  end

  @impl true
  def await_ready(runtime, opts) do
    Runtime.await_ready(runtime, Keyword.get(opts, :timeout, 5_000))
  catch
    :exit, reason -> {:error, {:sensor_manager_runtime_unavailable, reason}}
  end

  def child_spec(%Init{} = init) do
    Supervisor.child_spec({Runtime, init}, id: SensorManager)
  end
end

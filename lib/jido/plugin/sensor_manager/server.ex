defmodule Jido.Plugin.SensorManager.Server do
  @moduledoc "Owns supervised sensor reconciliation after Agent commits."
  @behaviour Jido.Plugin

  alias Jido.Plugin.{DirectiveContext, Init}
  alias Jido.Plugin.SensorManager
  alias Jido.Plugin.SensorManager.Runtime

  @impl true
  def validate_options(opts) do
    case Keyword.fetch(opts, :retry_delay_ms) do
      :error ->
        :ok

      {:ok, delay} when is_integer(delay) and delay in 1..4_294_967_295 ->
        :ok

      {:ok, delay} ->
        {:error,
         Jido.Error.validation_error("Sensor Manager retry delay is invalid",
           kind: :config,
           details: %{retry_delay_ms: delay}
         )}
    end
  end

  @impl true
  def dispatch(runtime, _directive, %DirectiveContext{} = context, opts) do
    timeout = timeout(opts)
    Runtime.reconcile(runtime, context.plugin_state.desired, context.state_version, timeout)
  catch
    :exit, reason -> {:error, {:sensor_manager_runtime_unavailable, reason}}
  end

  @impl true
  def await_ready(runtime, opts) do
    Runtime.await_ready(runtime, timeout(opts))
  catch
    :exit, reason -> {:error, {:sensor_manager_runtime_unavailable, reason}}
  end

  @impl true
  def child_spec(%Init{} = init) do
    Supervisor.child_spec({Runtime, init}, id: SensorManager)
  end

  defp timeout(opts), do: Keyword.get(opts, :timeout, 5_000)
end

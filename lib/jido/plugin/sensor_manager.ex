defmodule Jido.Plugin.SensorManager do
  @moduledoc """
  Keeps supervised sensor processes aligned with portable Agent state.

  A sensor is a standard OTP child that accepts a
  `Jido.Plugin.SensorManager.Init` value. It sends input to the owning Agent
  with `Jido.AgentServer.cast(init.agent_server, signal)`.

  `start/3` adds or replaces one tagged sensor. `stop/1` removes it. The
  manager restarts a failed sensor while its tag remains desired. Reconciliation
  ignores effects from a revision that is at or below the last successful
  revision, so an old retry cannot replace a newer sensor set.

  The `:retry_delay_ms` Plugin option defaults to `1_000`. It must be an
  integer from `1` through `4_294_967_295`; invalid values fail Agent startup
  before a sensor process starts.
  """

  use Jido.Plugin, option_keys: [agent_server: [:retry_delay_ms]]

  alias Jido.Joi
  alias Jido.Plugin.{Context, Init}
  alias Jido.Plugin.SensorManager.{Runtime, Start, Stop}

  @runtime_timeout 5_000
  @sensor_schema Joi.object(%{module: Joi.module(), config: Joi.map() |> Joi.default(%{})})
  @state_schema Joi.object(%{desired: Joi.map(Joi.any(), @sensor_schema) |> Joi.default(%{})})
                |> Joi.default(%{})

  @typedoc "One Sensor Manager Plugin option."
  @type option :: {:retry_delay_ms, 1..4_294_967_295}

  @impl true
  def state_spec(_opts), do: {:sensors, @state_schema}

  @impl true
  def directives(_opts), do: [Start, Stop]

  @impl true
  def reduce(reduction, _opts) do
    desired =
      Enum.reduce(reduction.directives, reduction.plugin_state.desired, &apply_directive/2)

    {:ok, %{reduction.plugin_state | desired: desired}}
  end

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
  def dispatch(runtime, _directive, %Context{phase: :directive} = context, _opts) do
    Runtime.reconcile(
      runtime,
      context.plugin_state.desired,
      context.state_version,
      @runtime_timeout
    )
  catch
    :exit, reason -> {:error, {:sensor_manager_runtime_unavailable, reason}}
  end

  @impl true
  def await_ready(runtime, _opts) do
    Runtime.await_ready(runtime, @runtime_timeout)
  catch
    :exit, reason -> {:error, {:sensor_manager_runtime_unavailable, reason}}
  end

  @impl true
  def child_spec(%Init{} = init) do
    Supervisor.child_spec({Runtime, init}, id: init.module)
  end

  @doc "Creates a Directive that adds or replaces one tagged sensor."
  @spec start(term(), module(), map()) :: Start.t()
  def start(tag, sensor, config \\ %{}), do: %Start{tag: tag, sensor: sensor, config: config}

  @doc "Creates a Directive that removes one tagged sensor."
  @spec stop(term()) :: Stop.t()
  def stop(tag), do: %Stop{tag: tag}

  defp apply_directive(%Start{tag: tag, sensor: sensor, config: config}, desired),
    do: Map.put(desired, tag, %{module: sensor, config: config})

  defp apply_directive(%Stop{tag: tag}, desired), do: Map.delete(desired, tag)
  defp apply_directive(_other, desired), do: desired
end

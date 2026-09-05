defmodule Jido.Plugin.SensorManager do
  @moduledoc """
  Keeps supervised sensor processes aligned with portable Agent state.

  A sensor is a standard OTP child that accepts a
  `Jido.Plugin.SensorManager.Init` value. It sends input to the owning Agent
  with `Jido.AgentServer.cast(init.agent_server, signal)`.

  `start/3` adds or replaces one tagged sensor. `stop/1` removes it. The
  manager restarts a failed sensor while its tag remains desired.
  """

  use Jido.Plugin

  alias Jido.Plugin.{DirectiveContext, Init}
  alias Jido.Plugin.SensorManager.{Runtime, Start, Stop}

  @sensor_schema Zoi.object(%{
                   module: Zoi.module(),
                   config: Zoi.map() |> Zoi.default(%{})
                 })

  @state_schema Zoi.object(%{
                  desired: Zoi.map(Zoi.any(), @sensor_schema) |> Zoi.default(%{})
                })
                |> Zoi.default(%{desired: %{}})

  @doc "Creates a Directive that adds or replaces one tagged sensor."
  @spec start(term(), module(), map()) :: Start.t()
  def start(tag, sensor, config \\ %{}), do: %Start{tag: tag, sensor: sensor, config: config}

  @doc "Creates a Directive that removes one tagged sensor."
  @spec stop(term()) :: Stop.t()
  def stop(tag), do: %Stop{tag: tag}

  @impl Jido.Plugin
  def state_spec(_opts), do: {:sensors, @state_schema}

  @impl Jido.Plugin
  def directives(_opts), do: [Start, Stop]

  @impl Jido.Plugin
  def validate_directive(%Start{} = directive, _opts) do
    with {:ok, directive} <- Zoi.parse(Start.schema(), Map.from_struct(directive)),
         :ok <- validate_tag(directive.tag),
         :ok <- validate_sensor(directive.sensor),
         :ok <- Jido.Action.validate_static_data(directive.config) do
      {:ok, directive}
    else
      {:error, reason} when is_binary(reason) ->
        invalid("Sensor config must contain portable data", %{reason: reason})

      {:error, _reason} = error ->
        error
    end
  end

  def validate_directive(%Stop{} = directive, _opts) do
    with {:ok, directive} <- Zoi.parse(Stop.schema(), Map.from_struct(directive)),
         :ok <- validate_tag(directive.tag) do
      {:ok, directive}
    end
  end

  @impl Jido.Plugin
  def update_state(state, directives, _opts) do
    desired =
      Enum.reduce(directives, state.desired, fn
        %Start{tag: tag, sensor: sensor, config: config}, desired ->
          Map.put(desired, tag, %{module: sensor, config: config})

        %Stop{tag: tag}, desired ->
          Map.delete(desired, tag)
      end)

    {:ok, %{state | desired: desired}}
  end

  @impl Jido.Plugin
  def dispatch(runtime, _directive, %DirectiveContext{} = context, opts) do
    timeout = Keyword.get(opts, :timeout, 5_000)
    Runtime.reconcile(runtime, context.plugin_state.desired, context.state_version, timeout)
  catch
    :exit, reason -> {:error, {:sensor_manager_runtime_unavailable, reason}}
  end

  @impl Jido.Plugin
  def await_ready(runtime, opts) do
    Runtime.await_ready(runtime, Keyword.get(opts, :timeout, 5_000))
  catch
    :exit, reason -> {:error, {:sensor_manager_runtime_unavailable, reason}}
  end

  @doc false
  def child_spec(%Init{} = init) do
    Supervisor.child_spec({Runtime, init}, id: __MODULE__)
  end

  defp validate_tag(nil), do: invalid("Sensor tag must not be nil", %{tag: nil})

  defp validate_tag(tag) do
    case Jido.Action.validate_static_data(tag) do
      :ok -> :ok
      {:error, reason} -> invalid("Sensor tag must contain portable data", %{reason: reason})
    end
  end

  defp validate_sensor(module) do
    with {:module, ^module} <- Code.ensure_loaded(module),
         true <- function_exported?(module, :child_spec, 1) do
      :ok
    else
      _invalid -> invalid("Sensor must define child_spec/1", %{sensor: module})
    end
  end

  defp invalid(message, details) do
    {:error, Jido.Error.validation_error(message, kind: :config, details: details)}
  end
end

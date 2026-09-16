defmodule Jido.Plugin.SensorManager do
  @moduledoc """
  Keeps supervised sensor processes aligned with portable Agent state.

  A sensor is a standard OTP child that accepts a
  `Jido.Plugin.SensorManager.Init` value. It sends input to the owning Agent
  with `Jido.AgentServer.cast(init.agent_server, signal)`.

  `start/3` adds or replaces one tagged sensor. `stop/1` removes it. The
  manager restarts a failed sensor while its tag remains desired.
  """

  use Jido.Plugin,
    agent: Jido.Plugin.SensorManager.Agent,
    agent_server: Jido.Plugin.SensorManager.Server

  alias Jido.Plugin.SensorManager.{Start, Stop}

  @doc "Creates a Directive that adds or replaces one tagged sensor."
  @spec start(term(), module(), map()) :: Start.t()
  def start(tag, sensor, config \\ %{}), do: %Start{tag: tag, sensor: sensor, config: config}

  @doc "Creates a Directive that removes one tagged sensor."
  @spec stop(term()) :: Stop.t()
  def stop(tag), do: %Stop{tag: tag}

  @doc false
  def validate_tag(nil), do: invalid("Sensor tag must not be nil", %{tag: nil})

  def validate_tag(tag) do
    case Jido.Action.validate_static_data(tag) do
      :ok -> :ok
      {:error, reason} -> invalid("Sensor tag must contain portable data", %{reason: reason})
    end
  end

  @doc false
  def validate_sensor(module) do
    with {:module, ^module} <- Code.ensure_loaded(module),
         true <- function_exported?(module, :child_spec, 1) do
      :ok
    else
      _invalid -> invalid("Sensor must define child_spec/1", %{sensor: module})
    end
  end

  @doc false
  def invalid(message, details) do
    {:error, Jido.Error.validation_error(message, kind: :config, details: details)}
  end
end

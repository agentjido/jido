defmodule Jido.Signal.Serialization.Config do
  @moduledoc """
  Configuration management for serialization settings.

  This module provides functions to get and set default serialization
  configuration for the Jido application.

  ## Configuration Options

  The following configuration keys are supported under the `:jido` application:

  - `:default_serializer` - The default serializer module to use (default: JsonSerializer)
  - `:default_type_provider` - The default type provider module to use (default: ModuleNameTypeProvider)

  ## Example Configuration

      # In your config.exs or runtime.exs
      config :jido,
        default_serializer: Jido.Signal.Serialization.ErlangTermSerializer,
        default_type_provider: Jido.Signal.Serialization.ModuleNameTypeProvider

  ## Runtime Configuration

  You can also change the configuration at runtime:

      Jido.Signal.Serialization.Config.set_default_serializer(MyCustomSerializer)
      Jido.Signal.Serialization.Config.set_default_type_provider(MyCustomTypeProvider)
  """

  alias Jido.Signal.Serialization.{JsonSerializer, ModuleNameTypeProvider}

  @doc """
  Get the configured default serializer.
  """
  @spec default_serializer() :: module()
  def default_serializer do
    Application.get_env(:jido, :default_serializer, JsonSerializer)
  end

  @doc """
  Get the configured default type provider.
  """
  @spec default_type_provider() :: module()
  def default_type_provider do
    Application.get_env(:jido, :default_type_provider, ModuleNameTypeProvider)
  end

  @doc """
  Set the default serializer at runtime.
  """
  @spec set_default_serializer(module()) :: :ok
  def set_default_serializer(serializer) when is_atom(serializer) do
    Application.put_env(:jido, :default_serializer, serializer)
  end

  @doc """
  Set the default type provider at runtime.
  """
  @spec set_default_type_provider(module()) :: :ok
  def set_default_type_provider(type_provider) when is_atom(type_provider) do
    Application.put_env(:jido, :default_type_provider, type_provider)
  end

  @doc """
  Get all serialization configuration as a keyword list.
  """
  @spec all() :: keyword()
  def all do
    [
      default_serializer: default_serializer(),
      default_type_provider: default_type_provider()
    ]
  end

  @doc """
  Validate that the configured serializer implements the Serializer behaviour.
  """
  @spec validate_serializer(module()) :: :ok | {:error, String.t()}
  def validate_serializer(serializer) do
    if Code.ensure_loaded?(serializer) do
      behaviours = serializer.module_info(:attributes)[:behaviour] || []

      if Jido.Signal.Serialization.Serializer in behaviours do
        :ok
      else
        {:error,
         "#{inspect(serializer)} does not implement Jido.Signal.Serialization.Serializer behaviour"}
      end
    else
      {:error, "#{inspect(serializer)} module not found"}
    end
  end

  @doc """
  Validate that the configured type provider implements the TypeProvider behaviour.
  """
  @spec validate_type_provider(module()) :: :ok | {:error, String.t()}
  def validate_type_provider(type_provider) do
    if Code.ensure_loaded?(type_provider) do
      behaviours = type_provider.module_info(:attributes)[:behaviour] || []

      if Jido.Signal.Serialization.TypeProvider in behaviours do
        :ok
      else
        {:error,
         "#{inspect(type_provider)} does not implement Jido.Signal.Serialization.TypeProvider behaviour"}
      end
    else
      {:error, "#{inspect(type_provider)} module not found"}
    end
  end

  @doc """
  Validate the current configuration.
  """
  @spec validate() :: :ok | {:error, [String.t()]}
  def validate do
    errors =
      []
      |> check_serializer()
      |> check_type_provider()

    case errors do
      [] -> :ok
      errors -> {:error, errors}
    end
  end

  defp check_serializer(errors) do
    case validate_serializer(default_serializer()) do
      :ok -> errors
      {:error, msg} -> [msg | errors]
    end
  end

  defp check_type_provider(errors) do
    case validate_type_provider(default_type_provider()) do
      :ok -> errors
      {:error, msg} -> [msg | errors]
    end
  end
end

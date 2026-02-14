defmodule Jido.Observe.EventContract do
  @moduledoc """
  Minimal helpers for validating custom telemetry event contracts.

  Downstream packages can use this module to enforce stable required keys for
  metadata and measurements before emitting namespaced events.
  """

  @type event_prefix :: [atom()]
  @type key :: atom() | String.t()
  @type required_keys :: [key()]

  @type metadata_error :: {:missing_metadata_keys, required_keys()}
  @type measurements_error :: {:missing_measurement_keys, required_keys()}

  @type event_error ::
          {:invalid_event_contract,
           %{
             event: event_prefix(),
             missing_metadata_keys: required_keys(),
             missing_measurement_keys: required_keys()
           }}

  @doc """
  Validates that metadata contains all required keys.
  """
  @spec validate_metadata(map(), required_keys()) :: {:ok, map()} | {:error, metadata_error()}
  def validate_metadata(metadata, required_keys)
      when is_map(metadata) and is_list(required_keys) do
    missing_keys = missing_required_keys(metadata, required_keys)

    case missing_keys do
      [] -> {:ok, metadata}
      _ -> {:error, {:missing_metadata_keys, missing_keys}}
    end
  end

  @doc """
  Validates that measurements contain all required keys.
  """
  @spec validate_measurements(map(), required_keys()) ::
          {:ok, map()} | {:error, measurements_error()}
  def validate_measurements(measurements, required_keys)
      when is_map(measurements) and is_list(required_keys) do
    missing_keys = missing_required_keys(measurements, required_keys)

    case missing_keys do
      [] -> {:ok, measurements}
      _ -> {:error, {:missing_measurement_keys, missing_keys}}
    end
  end

  @doc """
  Validates event metadata and measurements against required keys.

  ## Options

  - `:required_metadata` - Required metadata keys.
  - `:required_measurements` - Required measurement keys.
  """
  @spec validate_event(event_prefix(), map(), map(), keyword()) ::
          {:ok, %{event: event_prefix(), measurements: map(), metadata: map()}}
          | {:error, event_error()}
  def validate_event(event_prefix, measurements, metadata, opts \\ [])

  def validate_event(event_prefix, measurements, metadata, opts)
      when is_list(event_prefix) and is_map(measurements) and is_map(metadata) and is_list(opts) do
    required_metadata = Keyword.get(opts, :required_metadata, [])
    required_measurements = Keyword.get(opts, :required_measurements, [])

    missing_metadata = missing_required_keys(metadata, required_metadata)
    missing_measurements = missing_required_keys(measurements, required_measurements)

    if missing_metadata == [] and missing_measurements == [] do
      {:ok, %{event: event_prefix, measurements: measurements, metadata: metadata}}
    else
      {:error,
       {:invalid_event_contract,
        %{
          event: event_prefix,
          missing_metadata_keys: missing_metadata,
          missing_measurement_keys: missing_measurements
        }}}
    end
  end

  defp missing_required_keys(map, required_keys) do
    required_keys
    |> Enum.uniq()
    |> Enum.reject(&key_present?(map, &1))
  end

  defp key_present?(map, key) when is_atom(key) do
    Map.has_key?(map, key) or Map.has_key?(map, Atom.to_string(key))
  end

  defp key_present?(map, key), do: Map.has_key?(map, key)
end

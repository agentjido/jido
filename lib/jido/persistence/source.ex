defmodule Jido.Persistence.Source do
  @moduledoc false

  alias Jido.Persistence.Store

  @operation_options [
    :expected_revision,
    :instance,
    :namespace,
    :partition,
    :reason,
    :revision,
    :server_turn
  ]

  defdelegate normalize_adapter(config), to: Store

  def resolve_config(:inherit, jido), do: resolve_instance_config(jido)
  def resolve_config(nil, _jido), do: {:ok, nil}

  def resolve_config(config, _jido) do
    config
    |> normalize_adapter_result()
    |> validate_adapter_result()
  end

  def resolve(source, opts) do
    {config_result, default_instance} =
      cond do
        is_atom(source) and not is_nil(source) and
            function_exported?(source, :__jido_persistence__, 0) ->
          {resolve_instance_config(source), source}

        live_instance?(source) ->
          {resolve_instance_config(source), source}

        true ->
          {resolve_config(source, nil), nil}
      end

    with {:ok, config} <- config_result,
         {:ok, config} <- require_adapter(config) do
      {:ok, config, Keyword.get(opts, :instance, default_instance)}
    end
  end

  @spec validate_operation_options(term(), [atom()]) :: :ok | {:error, term()}
  def validate_operation_options(opts, allowed \\ @operation_options) do
    cond do
      not Keyword.keyword?(opts) ->
        {:error, {:invalid_persistence_options, opts}}

      Keyword.has_key?(opts, :write_authority) ->
        {:error, {:unsupported_persistence_option, :write_authority}}

      true ->
        validate_option_keys(Keyword.keys(opts), allowed)
    end
  end

  defp validate_option_keys(keys, allowed) do
    duplicate_keys = keys |> Enum.frequencies() |> duplicate_keys(keys)
    unsupported_keys = keys |> Enum.reject(&(&1 in allowed)) |> Enum.uniq()

    cond do
      duplicate_keys != [] ->
        {:error, {:invalid_persistence_options, {:duplicate_options, duplicate_keys}}}

      unsupported_keys != [] ->
        {:error, {:unsupported_persistence_options, unsupported_keys}}

      true ->
        :ok
    end
  end

  defp duplicate_keys(frequencies, keys) do
    keys
    |> Enum.filter(&(Map.fetch!(frequencies, &1) > 1))
    |> Enum.uniq()
  end

  defp resolve_instance_config(jido) do
    config =
      cond do
        live_instance?(jido) ->
          Jido.instance_persistence(jido)

        is_atom(jido) and function_exported?(jido, :__jido_persistence__, 0) ->
          jido.__jido_persistence__()

        true ->
          nil
      end

    config
    |> normalize_adapter_result()
    |> validate_adapter_result()
  rescue
    error -> {:error, {:invalid_persistence_config, error}}
  end

  defp live_instance?(source) when is_atom(source) and not is_nil(source) do
    is_pid(Process.whereis(source)) and
      is_pid(Process.whereis(Jido.runtime_store_name(source)))
  end

  defp live_instance?(_source), do: false

  defp require_adapter(nil), do: {:error, :persistence_not_configured}
  defp require_adapter(config), do: {:ok, config}

  defp normalize_adapter_result(config) do
    {:ok, normalize_adapter(config)}
  rescue
    error -> {:error, {:invalid_persistence_config, error}}
  end

  defp validate_adapter_result({:ok, nil}), do: {:ok, nil}

  defp validate_adapter_result({:ok, config}), do: Store.open(config)

  defp validate_adapter_result({:error, _reason} = error), do: error
end

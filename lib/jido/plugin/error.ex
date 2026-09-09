defmodule Jido.Plugin.Error do
  @moduledoc false

  alias Jido.Error

  def safe_apply(package, facet, function, args, message) do
    apply(facet, function, args)
  rescue
    error -> {:error, callback_error(message, package, facet, function, :error, error)}
  catch
    kind, reason ->
      {:error, callback_error(message, package, facet, function, kind, reason)}
  end

  def invalid_callback(message, package, facet, details \\ %{}) do
    {:error,
     execution(
       message,
       package,
       facet,
       Map.put_new(details, :code, :plugin_invalid_callback_result)
     )}
  end

  def validation(message, details) do
    {:error, Error.validation_error(message, kind: :config, details: details)}
  end

  def execution(message, package, facet, details) do
    details = Map.put(details, :plugin, package)
    details = if facet == package, do: details, else: Map.put(details, :facet, facet)

    Error.execution_error(message,
      details: details
    )
  end

  defp callback_error(message, package, facet, callback, :error, error) do
    execution(message, package, facet, %{
      code: :plugin_callback_failed,
      callback: callback,
      error: error
    })
  end

  defp callback_error(message, package, facet, callback, kind, reason) do
    execution(message, package, facet, %{
      code: :plugin_callback_failed,
      callback: callback,
      kind: kind,
      reason: reason
    })
  end
end

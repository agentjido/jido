defmodule Jido.Agent.Callback do
  @moduledoc false

  alias Jido.Error

  @doc false
  def invoke(module, callback, args) do
    case capture(module, callback, args) do
      {:ok, result} -> result
      {:error, kind, reason} -> failed(module, callback, kind, reason)
    end
  end

  @doc false
  def capture(module, callback, args) do
    {:ok, apply(module, callback, args)}
  rescue
    error -> {:error, :error, error}
  catch
    kind, reason -> {:error, kind, reason}
  end

  defp failed(module, callback, kind, reason) do
    {:error,
     Error.execution_error("Agent callback failed",
       details: %{
         code: :agent_callback_failed,
         module: module,
         callback: callback,
         kind: kind,
         reason: reason
       }
     )}
  end
end

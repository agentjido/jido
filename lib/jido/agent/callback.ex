defmodule Jido.Agent.Callback do
  @moduledoc false

  @doc false
  def invoke(module, callback, args) do
    apply(module, callback, args)
  rescue
    error -> failed(module, callback, :error, error)
  catch
    kind, reason -> failed(module, callback, kind, reason)
  end

  defp failed(module, callback, kind, reason) do
    {:error,
     Jido.Error.execution_error("Agent callback failed",
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

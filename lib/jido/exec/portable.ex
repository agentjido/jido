defmodule Jido.Exec.Portable do
  @moduledoc false

  alias Jido.Action.Error
  alias Jido.PortableTerm

  @doc false
  @spec validate(term(), atom()) :: :ok | {:error, Exception.t()}
  def validate(value, field) do
    case PortableTerm.validate_local(value, field) do
      :ok ->
        :ok

      {:error, type, path} ->
        {:error,
         Error.execution_error("durable execution data contains a process-local value", %{
           phase: :durability,
           reason: :non_portable_durable_value,
           type: type,
           path: path,
           retry: false
         })}
    end
  end
end

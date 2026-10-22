defmodule Jido.Agent.Error do
  @moduledoc "An authoring error with a code, field path, and details."
  defexception [:message, :code, path: [], details: %{}]
  @type t :: %__MODULE__{message: String.t(), code: atom(), path: list(), details: map()}

  @doc false
  def fail(code, path, message, details \\ %{}),
    do:
      {:error, %__MODULE__{code: code, path: List.wrap(path), message: message, details: details}}

  @doc false
  def at({:error, %__MODULE__{} = error}, path),
    do: {:error, %{error | path: List.wrap(path) ++ error.path}}

  def at(result, _path), do: result

  @doc false
  def unwrap!({:ok, value}), do: value
  def unwrap!({:error, error}), do: raise(error)
end

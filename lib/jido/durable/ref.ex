defmodule Jido.Durable.Ref do
  @moduledoc """
  Portable identity for one durable Flow execution.

  A reference contains no PID, Runner, storage adapter, or runtime context.
  Pass the Jido instance that owns the execution to `Jido.Durable` operations.
  """

  alias Jido.Error
  alias Jido.Instance.NamespaceRegistry

  @enforce_keys [:namespace, :id]
  defstruct @enforce_keys

  @type t :: %__MODULE__{namespace: String.t(), id: String.t()}

  @doc "Builds one durable reference in a running Jido instance namespace."
  @spec new(atom(), String.t()) :: {:ok, t()} | {:error, Error.ValidationError.t()}
  def new(jido, id) when is_atom(jido) and is_binary(id) and byte_size(id) > 0 do
    case NamespaceRegistry.namespace(jido) do
      namespace when is_binary(namespace) and byte_size(namespace) > 0 ->
        {:ok, %__MODULE__{namespace: namespace, id: id}}

      _missing ->
        invalid("durable execution requires a running Jido instance with a namespace", %{
          instance: jido
        })
    end
  end

  def new(jido, id),
    do: invalid("durable execution ID must be a nonempty string", %{instance: jido, id: id})

  @doc false
  @spec execution_id(t()) :: tuple()
  def execution_id(%__MODULE__{namespace: namespace, id: id}),
    do: {:jido_execution, namespace, :durable, :flow, id}

  defp invalid(message, details),
    do:
      {:error,
       Error.validation_error(message,
         kind: :config,
         subject: __MODULE__,
         details: details
       )}
end

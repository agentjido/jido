defmodule Jido.Flow.Form.Reduce do
  @moduledoc """
  The canonical compound form for an ordered Reduce operation.

  Reduce starts with an explicit initial value. It calls one Instruction for
  each collection item in order. The previous call result is the accumulator
  for the next call. An empty collection returns the initial value. The first
  error stops the reduction.
  """

  alias Jido.Flow
  alias Jido.Flow.{Call, Error, Value}
  alias Jido.Flow.Form.Validation

  @form_fields [
    :type,
    :collection,
    :initial,
    :call,
    :action,
    :params,
    :context,
    :metadata,
    :policy,
    :timeout_ms,
    :retry
  ]

  @type t :: %__MODULE__{
          collection: Flow.Value.t(),
          initial: Flow.Value.t(),
          call: Call.t()
        }

  @enforce_keys [:collection, :initial, :call]
  defstruct [:collection, :initial, :call]

  @doc false
  @spec normalize(term()) :: {:ok, t()} | {:error, Exception.t()}
  def normalize(%__MODULE__{} = form) do
    build(%{
      collection: form.collection,
      initial: form.initial,
      call: form.call
    })
  end

  def normalize(%{} = attrs) when not is_struct(attrs) do
    with {:ok, attrs} <- Validation.normalize_fields(attrs, @form_fields, "Reduce"),
         :ok <- Validation.validate_tag(attrs, :reduce, "Reduce"),
         {:ok, collection} <- Validation.collection(attrs, "Reduce"),
         {:ok, initial} <- fetch_initial(attrs),
         {:ok, call} <- Validation.call(attrs, "Reduce") do
      build(%{collection: collection, initial: initial, call: call})
    end
  end

  def normalize(value) do
    {:error,
     Error.validation_error("Reduce form must be a map", %{reason: :reduce, value: value})}
  end

  defp build(attrs) do
    with {:ok, collection} <- Value.prepare(attrs.collection, :flow),
         {:ok, initial} <- Value.prepare(attrs.initial, :flow),
         {:ok, call} <- Validation.normalize_call(attrs.call, :reduce, "Reduce body"),
         {:ok, call} <- Validation.require_fail_fast(call, "Reduce body") do
      {:ok,
       %__MODULE__{
         collection: collection,
         initial: initial,
         call: call
       }}
    end
  end

  defp fetch_initial(%{initial: value}), do: {:ok, value}

  defp fetch_initial(_attrs) do
    {:error,
     Error.validation_error("Reduce initial value is required", %{reason: :initial_required})}
  end
end

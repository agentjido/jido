defmodule Jido.Flow.Form.Map do
  @moduledoc """
  The canonical compound form for an ordered Map operation.

  Map applies one Instruction to each value in a collection. The item call
  stays inside the named form. It does not become a Flow graph vertex.
  """

  alias Jido.Flow
  alias Jido.Flow.{Call, Error, Value}
  alias Jido.Flow.Form.Validation

  @form_fields [
    :type,
    :collection,
    :call,
    :action,
    :params,
    :context,
    :metadata,
    :policy,
    :timeout_ms,
    :retry,
    :on_error
  ]

  @type on_error :: :fail_fast | :collect_errors
  @type t :: %__MODULE__{
          collection: Flow.Value.t(),
          call: Call.t(),
          on_error: on_error()
        }

  @enforce_keys [:collection, :call]
  defstruct [:collection, :call, on_error: :fail_fast]

  @doc false
  @spec normalize(term()) :: {:ok, t()} | {:error, Exception.t()}
  def normalize(%__MODULE__{} = form) do
    build(%{
      collection: form.collection,
      call: form.call,
      on_error: form.on_error
    })
  end

  def normalize(%{} = attrs) when not is_struct(attrs) do
    with {:ok, attrs} <- Validation.normalize_fields(attrs, @form_fields, "Map"),
         :ok <- Validation.validate_tag(attrs, :map, "Map"),
         {:ok, collection} <- Validation.collection(attrs, "Map"),
         {:ok, call} <- Validation.call(attrs, "Map") do
      build(%{
        collection: collection,
        call: call,
        on_error: Map.get(attrs, :on_error, :fail_fast)
      })
    end
  end

  def normalize(value),
    do: {:error, Error.validation_error("Map form must be a map", %{reason: :map, value: value})}

  defp build(attrs) do
    with {:ok, collection} <- Value.prepare(attrs.collection, :flow),
         {:ok, call} <- Validation.normalize_call(attrs.call, :map, "Map body"),
         {:ok, call} <- Validation.require_fail_fast(call, "Map body"),
         :ok <- Validation.validate_on_error(attrs.on_error, "Map") do
      {:ok,
       %__MODULE__{
         collection: collection,
         call: call,
         on_error: attrs.on_error
       }}
    end
  end
end

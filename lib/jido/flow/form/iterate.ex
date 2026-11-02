defmodule Jido.Flow.Form.Iterate do
  @moduledoc """
  The canonical form for one bounded state loop.

  Iterate supports a fixed Repeat count or a Boolean While condition with an
  explicit maximum. The body is one Action or Flow Instruction.
  """

  alias Jido.Flow.{Call, Config, Error, Ref, Value}
  alias Jido.Flow.Form.Validation

  @maximum_iterations 10_000
  @form_fields [
    :type,
    :state_schema,
    :initial,
    :call,
    :action,
    :params,
    :context,
    :metadata,
    :policy,
    :timeout_ms,
    :retry,
    :update,
    :while,
    :repeat,
    :max_iterations
  ]

  @type mode :: {:repeat, pos_integer()} | {:while, Jido.Flow.Value.t(), pos_integer()}
  @type t :: %__MODULE__{
          state_schema: Jido.Action.schema(),
          initial: Jido.Flow.Value.t(),
          call: Call.t(),
          update: Jido.Flow.Value.t(),
          mode: mode()
        }

  @enforce_keys [:state_schema, :initial, :call, :update, :mode]
  defstruct [:state_schema, :initial, :call, :update, :mode]

  @doc false
  @spec normalize(term()) :: {:ok, t()} | {:error, Exception.t()}
  def normalize(%__MODULE__{} = form) do
    attrs = %{
      state_schema: form.state_schema,
      initial: form.initial,
      call: form.call,
      update: form.update,
      repeat: nil,
      while: nil,
      max_iterations: nil
    }

    case form.mode do
      {:repeat, count} ->
        build(Map.put(attrs, :repeat, count))

      {:while, condition, maximum} ->
        build(Map.merge(attrs, %{while: condition, max_iterations: maximum}))
    end
  end

  def normalize(%{} = attrs) when not is_struct(attrs) do
    with {:ok, attrs} <-
           Validation.normalize_fields(attrs, @form_fields, "Iterate"),
         :ok <- Validation.validate_tag(attrs, :iterate, "Iterate"),
         {:ok, call} <- Validation.call(attrs, "Iterate"),
         {:ok, initial} <- required(attrs, :initial),
         {:ok, schema} <- required(attrs, :state_schema) do
      build(%{
        state_schema: schema,
        initial: initial,
        call: call,
        update: Map.get(attrs, :update, Ref.body_result()),
        while: Map.get(attrs, :while),
        repeat: Map.get(attrs, :repeat),
        max_iterations: Map.get(attrs, :max_iterations)
      })
    end
  end

  def normalize(value) do
    {:error,
     Error.validation_error("Iterate form must be a map", %{reason: :iterate, value: value})}
  end

  defp build(attrs) do
    with {:ok, schema} <- Config.schema(attrs.state_schema, "Iterate state schema"),
         {:ok, initial} <- Value.prepare(attrs.initial, :flow),
         {:ok, call} <- Validation.normalize_call(attrs.call, :iterate_params, "Iterate body"),
         {:ok, call} <- Validation.require_fail_fast(call, "Iterate body"),
         {:ok, update} <- Value.prepare(attrs.update, :iterate_update),
         {:ok, mode} <- mode(attrs) do
      {:ok,
       %__MODULE__{
         state_schema: schema,
         initial: initial,
         call: call,
         update: update,
         mode: mode
       }}
    end
  end

  defp mode(%{repeat: count, while: nil, max_iterations: nil})
       when is_integer(count) and count in 1..@maximum_iterations,
       do: {:ok, {:repeat, count}}

  defp mode(%{repeat: nil, while: condition, max_iterations: maximum})
       when not is_nil(condition) and is_integer(maximum) and maximum in 1..@maximum_iterations do
    with {:ok, condition} <- Value.condition(condition, :iterate_condition),
         do: {:ok, {:while, condition, maximum}}
  end

  defp mode(_attrs) do
    {:error,
     Error.validation_error(
       "Iterate requires either repeat or while with max_iterations",
       %{reason: :mode}
     )}
  end

  defp required(attrs, field) do
    case Map.fetch(attrs, field) do
      {:ok, value} ->
        {:ok, value}

      :error ->
        {:error,
         Error.validation_error("Iterate #{field} is required", %{reason: :required, field: field})}
    end
  end
end

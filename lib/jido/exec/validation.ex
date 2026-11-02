defmodule Jido.Exec.Validation do
  @moduledoc false

  alias Jido.Action.{Error, Output}
  alias Jido.Exec.Source

  @doc false
  @spec input(module() | Jido.Flow.t() | nil, term(), map()) ::
          {:ok, term()} | {:error, Exception.t()}
  def input(target, value, details \\ %{}) do
    result =
      case target do
        nil ->
          {:ok, value}

        %Jido.Flow{} = flow ->
          schema(flow.schema, value, flow_details(flow, "Flow"), "Flow input must be a map")

        module ->
          callback(module, :validate_params, value, :input)
      end

    case result do
      {:error, error} -> {:error, Source.attach(error, nil, details)}
      result -> result
    end
  end

  @doc false
  @spec output(module() | Jido.Flow.t() | nil, term()) ::
          {:ok, term()} | {:error, Exception.t()}
  def output(nil, value), do: {:ok, value}

  def output(%Jido.Flow{} = flow, value),
    do: output_schema(flow.output_schema, value, flow_details(flow, "Flow output"))

  def output(module, value), do: callback(module, :validate_output, value, :output)

  @doc false
  @spec schema(term(), term(), map(), String.t() | nil) ::
          {:ok, map()} | {:error, Error.InvalidInputError.t()}
  def schema(schema, value, details, message \\ nil) do
    with {:ok, validated} <- Jido.Action.Validation.parse(schema, value, details) do
      if is_map(validated) do
        {:ok, validated}
      else
        {:error,
         Error.validation_error(
           message || "#{details.context} validation must return a map",
           Map.put(details, :value, validated)
         )}
      end
    end
  end

  @doc false
  @spec output_schema(term(), term(), map()) ::
          {:ok, map() | Output.t()} | {:error, Error.InvalidInputError.t()}
  def output_schema(schema, %Output{kind: :preserve} = output, details) do
    with {:ok, output} <- Output.validate(output),
         {:ok, value} when is_map(value) <-
           Jido.Action.Validation.parse_preserving_shape(schema, output.value, details) do
      {:ok, %{output | value: value}}
    else
      {:ok, value} ->
        {:error,
         Error.validation_error(
           "Action output validation must return a map",
           Map.put(details, :value, value)
         )}

      error ->
        error
    end
  end

  def output_schema(_schema, %Output{} = value, _details), do: Output.validate(value)

  def output_schema(schema, value, details),
    do: schema(schema, value, details, "Action output validation must return a map")

  @doc false
  @spec callback(module(), atom(), term(), :input | :output) ::
          {:ok, term()} | {:error, Exception.t()}
  def callback(module, callback, value, phase) do
    with {:ok, value} <- callback_input(module, value, phase) do
      apply_callback(module, callback, value, phase)
    end
  end

  defp callback_input(_module, %Output{} = output, :output), do: Output.validate(output)

  defp callback_input(module, value, :output) when not is_map(value) do
    {:error,
     Error.validation_error("Action output validation must return a map", %{
       context: "Action output",
       module: module,
       value: value
     })}
  end

  defp callback_input(_module, value, _phase), do: {:ok, value}

  defp apply_callback(module, callback, value, phase) do
    case apply(module, callback, [value], phase) do
      {:ok, {:ok, %Output{} = validated}} when phase == :output ->
        Output.validate(validated)

      {:ok, {:ok, validated}} when is_map(validated) ->
        {:ok, validated}

      {:ok, {:error, error}} when is_exception(error) ->
        {:error, error}

      {:ok, {:error, reason}} ->
        {:error,
         Error.validation_error("Action #{phase} validation failed", %{
           action: module,
           phase: phase,
           reason: reason
         })}

      {:ok, other} ->
        {:error,
         Error.internal_error("Action validator returned an invalid value", %{
           action: module,
           phase: phase,
           return: other,
           reason: :invalid_validator_return
         })}

      {:error, error} ->
        {:error, error}
    end
  end

  @doc false
  @spec apply(module(), atom(), list(), atom()) :: {:ok, term()} | {:error, Exception.t()}
  def apply(module, callback, args, phase) do
    {:ok, Kernel.apply(module, callback, args)}
  rescue
    exception ->
      failure(Exception.message(exception), module, phase, __STACKTRACE__, %{
        exception: exception.__struct__
      })
  catch
    kind, reason ->
      failure("Action #{phase} #{kind}", module, phase, __STACKTRACE__, %{
        kind: kind,
        reason: reason
      })
  end

  defp failure(message, module, phase, stacktrace, details) do
    error =
      Error.execution_error(
        message,
        Map.merge(details, %{action: module, phase: phase, stacktrace: stacktrace})
      )

    {:error, %{error | stacktrace: %Splode.Stacktrace{stacktrace: stacktrace}}}
  end

  defp flow_details(flow, context), do: %{module: Jido.Flow, flow: flow.name, context: context}
end

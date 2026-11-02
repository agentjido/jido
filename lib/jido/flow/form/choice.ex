defmodule Jido.Flow.Form.Choice do
  @moduledoc """
  The canonical compound form for an ordered Choice operation.

  Choice evaluates option conditions in order. It calls the Instruction for
  the first true condition. It calls the required fallback Instruction when
  no condition is true. An invalid condition result or a selected call error
  fails the Choice.
  """

  alias Jido.Flow.{Call, Error, Limits, Value}
  alias Jido.Flow.Form.Validation

  @form_fields [:type, :options, :fallback]

  @type option :: {String.t(), boolean() | Jido.Flow.Ref.t() | Jido.Expr.t(), Call.t()}
  @type t :: %__MODULE__{options: [option()], fallback: Call.t()}

  @enforce_keys [:options, :fallback]
  defstruct [:options, :fallback]

  @doc false
  @spec normalize(term()) :: {:ok, t()} | {:error, Exception.t()}
  def normalize(%__MODULE__{} = form),
    do: build(%{options: form.options, fallback: form.fallback})

  def normalize(%{} = attrs) when not is_struct(attrs) do
    with {:ok, attrs} <- Validation.normalize_fields(attrs, @form_fields, "Choice"),
         :ok <- Validation.validate_tag(attrs, :choice, "Choice"),
         {:ok, options} <- fetch_required(attrs, :options),
         {:ok, fallback} <- fetch_required(attrs, :fallback) do
      build(%{options: options, fallback: fallback})
    end
  end

  def normalize(value) do
    {:error,
     Error.validation_error("Choice form must be a map", %{reason: :choice, value: value})}
  end

  defp build(attrs) do
    with {:ok, options} <- normalize_options(attrs.options),
         {:ok, fallback} <- Validation.normalize_call(attrs.fallback, :flow, "Choice fallback"),
         {:ok, fallback} <- Validation.require_fail_fast(fallback, "Choice fallback") do
      {:ok, %__MODULE__{options: options, fallback: fallback}}
    end
  end

  defp normalize_options(options) when is_list(options) do
    cond do
      List.improper?(options) ->
        invalid_options("Choice options must be a proper list", :options)

      options == [] ->
        invalid_options("Choice must contain at least one option", :empty_options)

      true ->
        with :ok <- Limits.collection(options, :options) do
          options
          |> Enum.with_index()
          |> Enum.reduce_while({:ok, [], MapSet.new()}, fn {option, index},
                                                           {:ok, result, names} ->
            with {:ok, {name, condition, call}} <- normalize_option(option, index),
                 false <- MapSet.member?(names, name) do
              {:cont, {:ok, [{name, condition, call} | result], MapSet.put(names, name)}}
            else
              true ->
                {:halt,
                 invalid_options("Choice contains a duplicate option name", :duplicate_option,
                   option: elem(option, 0),
                   path: [:options, index]
                 )}

              {:error, error} ->
                {:halt, {:error, error}}
            end
          end)
          |> case do
            {:ok, result, _names} -> {:ok, Enum.reverse(result)}
            error -> error
          end
        end
    end
  end

  defp normalize_options(_options),
    do: invalid_options("Choice options must be a list", :options)

  defp normalize_option({name, condition, call}, index) do
    with {:ok, name} <-
           Validation.normalize_name(name, "Choice option", :option_name, [0]),
         {:ok, condition} <- Value.condition(condition, :flow),
         {:ok, call} <- Validation.normalize_call(call, :flow, "Choice option"),
         {:ok, call} <- Validation.require_fail_fast(call, "Choice option") do
      {:ok, {name, condition, call}}
    else
      {:error, error} -> {:error, Error.prefix_path(error, [:options, index])}
    end
  end

  defp normalize_option(_option, index),
    do:
      invalid_options("Choice option must be a {name, condition, call} tuple", :option,
        path: [:options, index]
      )

  defp fetch_required(attrs, field) do
    case Map.fetch(attrs, field) do
      {:ok, value} ->
        {:ok, value}

      :error ->
        invalid_options("Choice #{field} is required", required_reason(field))
    end
  end

  defp required_reason(:options), do: :options_required
  defp required_reason(:fallback), do: :fallback_required

  defp invalid_options(message, reason, details \\ []) do
    {:error, Error.validation_error(message, Map.new([reason: reason] ++ details))}
  end
end

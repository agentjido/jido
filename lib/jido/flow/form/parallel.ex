defmodule Jido.Flow.Form.Parallel do
  @moduledoc """
  The canonical compound form for a fixed Parallel operation.

  Parallel contains an ordered list of named independent Action calls. The
  calls stay inside the named form. They do not become Flow graph vertices.
  """

  alias Jido.Flow.{Call, Error, Limits}
  alias Jido.Flow.Form.Validation

  @form_fields [:type, :actions, :on_error]

  @type action :: {String.t(), Call.t()}
  @type on_error :: :fail_fast | :collect_errors
  @type t :: %__MODULE__{actions: [action()], on_error: on_error()}

  @enforce_keys [:actions]
  defstruct [:actions, on_error: :fail_fast]

  @doc false
  @spec normalize(term()) :: {:ok, t()} | {:error, Exception.t()}
  def normalize(%__MODULE__{} = form),
    do: build(%{actions: form.actions, on_error: form.on_error})

  def normalize(%{} = attrs) when not is_struct(attrs) do
    with {:ok, attrs} <- Validation.normalize_fields(attrs, @form_fields, "Parallel"),
         :ok <- Validation.validate_tag(attrs, :parallel, "Parallel"),
         {:ok, actions} <- fetch_actions(attrs) do
      build(%{actions: actions, on_error: Map.get(attrs, :on_error, :fail_fast)})
    end
  end

  def normalize(value) do
    {:error,
     Error.validation_error("Parallel form must be a map", %{
       reason: :parallel,
       value: value
     })}
  end

  defp build(attrs) do
    with {:ok, actions} <- normalize_actions(attrs.actions),
         :ok <- Validation.validate_on_error(attrs.on_error, "Parallel") do
      {:ok, %__MODULE__{actions: actions, on_error: attrs.on_error}}
    end
  end

  defp fetch_actions(%{actions: actions}), do: {:ok, actions}

  defp fetch_actions(_attrs),
    do: invalid_actions("Parallel actions are required", :actions_required)

  defp normalize_actions(actions) when is_list(actions) do
    cond do
      List.improper?(actions) ->
        invalid_actions("Parallel actions must be a proper list", :actions)

      actions == [] ->
        invalid_actions("Parallel must contain at least one Action", :empty_actions)

      true ->
        with :ok <- Limits.collection(actions, :actions) do
          actions
          |> Enum.with_index()
          |> Enum.reduce_while({:ok, [], MapSet.new()}, fn {action, index},
                                                           {:ok, result, names} ->
            with {:ok, {name, call}} <- normalize_action(action, index),
                 false <- MapSet.member?(names, name) do
              {:cont, {:ok, [{name, call} | result], MapSet.put(names, name)}}
            else
              true ->
                {:halt,
                 invalid_actions("Parallel contains a duplicate Action name", :duplicate_action,
                   action: elem(action, 0),
                   path: [:actions, index]
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

  defp normalize_actions(_actions),
    do: invalid_actions("Parallel actions must be a list", :actions)

  defp normalize_action({name, call}, index) do
    with {:ok, name} <-
           Validation.normalize_name(name, "Parallel Action", :action_name, [0]),
         {:ok, call} <- Validation.normalize_call(call, :flow, "Parallel Action"),
         {:ok, call} <- Validation.require_fail_fast(call, "Parallel Action") do
      {:ok, {name, call}}
    else
      {:error, error} -> {:error, Error.prefix_path(error, [:actions, index])}
    end
  end

  defp normalize_action(_action, index),
    do:
      invalid_actions("Parallel Action must be a {name, call} tuple", :action,
        path: [:actions, index]
      )

  defp invalid_actions(message, reason, details \\ []) do
    {:error, Error.validation_error(message, Map.new([reason: reason] ++ details))}
  end
end

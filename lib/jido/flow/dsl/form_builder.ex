defmodule Jido.Flow.DSL.FormBuilder do
  @moduledoc false

  alias Jido.Flow.{Error, Ref}
  alias Jido.Flow.DSL.{Name, ValueParser}
  alias Jido.Flow.DSL.Forms

  @doc false
  @spec build(struct()) ::
          {:ok, String.t(), map(), [String.t()]} | {:error, Exception.t()}
  def build(%Forms.Map{} = entity) do
    with {:ok, name} <- name(entity.name),
         {:ok, %{collection: collection, params: params}} <-
           ValueParser.parse_fields(entity, collection: :value, params: :value),
         {:ok, call} <- call(entity, params) do
      form = %{
        type: :map,
        collection: collection,
        call: call,
        on_error: entity.on_error
      }

      {:ok, name, form, entity.needs}
    end
  end

  def build(%Forms.Reduce{} = entity) do
    with {:ok, name} <- name(entity.name),
         {:ok, %{collection: collection, initial: initial, params: params}} <-
           ValueParser.parse_fields(entity,
             collection: :value,
             initial: :value,
             params: :value
           ),
         {:ok, call} <- call(entity, params) do
      form = %{
        type: :reduce,
        collection: collection,
        initial: initial,
        call: call
      }

      {:ok, name, form, entity.needs}
    end
  end

  def build(%Forms.Choice{} = entity) do
    with {:ok, name} <- name(entity.name),
         {:ok, options} <- choice_options(entity.options),
         {:ok, fallback} <- choice_fallback(entity.fallback) do
      form = %{type: :choice, options: options, fallback: fallback}
      {:ok, name, form, entity.needs}
    end
  end

  def build(%Forms.Parallel{} = entity) do
    with {:ok, name} <- name(entity.name),
         {:ok, actions} <- parallel_actions(entity.actions) do
      form = %{
        type: :parallel,
        actions: actions,
        on_error: entity.on_error
      }

      {:ok, name, form, entity.needs}
    end
  end

  def build(%Forms.Iterate{state: nil}) do
    {:error, Error.validation_error("Iterate state is required", %{reason: :state_required})}
  end

  def build(%Forms.Iterate{} = entity) do
    with {:ok, name} <- name(entity.name),
         {:ok, initial} <- ValueParser.parse(entity.state.initial),
         {:ok, params} <- ValueParser.parse(entity.params),
         {:ok, update} <- optional_value(entity.update, Ref.body_result()),
         {:ok, condition} <- optional_value(entity.while, nil),
         {:ok, call} <- call(entity, params) do
      form = %{
        type: :iterate,
        state_schema: entity.state.schema,
        initial: initial,
        call: call,
        update: update,
        while: condition,
        repeat: entity.repeat,
        max_iterations: entity.max_iterations
      }

      {:ok, name, form, entity.needs}
    end
  end

  def build(%Forms.Invoke{} = entity) do
    with {:ok, name} <- name(entity.name),
         {:ok, target} <- ValueParser.parse(entity.target),
         {:ok, params} <- ValueParser.parse(entity.params) do
      form = %{
        type: :invoke,
        target: target,
        targets: entity.targets,
        params: params,
        meta: entity.meta,
        policy: entity.policy,
        timeout_ms: entity.timeout_ms,
        retry: entity.retry,
        on_error: entity.on_error
      }

      {:ok, name, form, entity.needs}
    end
  end

  def build(%Forms.Wait.Await{} = entity) do
    with {:ok, name} <- name(entity.name),
         {:ok, %{match: match}} <- ValueParser.parse_fields(entity, match: :value) do
      form = %{type: :wait, clauses: [{:event, name, entity.event, match}]}
      {:ok, name, form, entity.needs}
    end
  end

  def build(%Forms.Wait.Timer{} = entity) do
    with {:ok, name} <- name(entity.name) do
      form = %{type: :wait, clauses: [{:timer, name, entity.after_ms}]}
      {:ok, name, form, entity.needs}
    end
  end

  def build(%Forms.Wait.Selection{} = entity) do
    with {:ok, name} <- name(entity.name),
         {:ok, clauses} <- wait_clauses(entity.clauses) do
      form = %{type: :wait, clauses: clauses}
      {:ok, name, form, entity.needs}
    end
  end

  def build(%{__struct__: module}) do
    {:error,
     Error.validation_error("Flow DSL entity is not supported", %{
       reason: :dsl_entity,
       entity: module
     })}
  end

  defp name(value) do
    case Name.normalize(value) do
      {:ok, name} -> {:ok, name}
      {:error, message} -> {:error, Error.validation_error(message, %{reason: :name})}
    end
  end

  defp call(entity, params \\ nil) do
    with {:ok, params} <- params(entity, params) do
      {:ok,
       %{
         type: :call,
         action: entity.action,
         params: params,
         metadata: entity.meta,
         policy: entity.policy,
         timeout_ms: entity.timeout_ms,
         retry: entity.retry,
         on_error: :fail_fast
       }}
    end
  end

  defp params(_entity, params) when not is_nil(params), do: {:ok, params}

  defp params(entity, nil) do
    with {:ok, %{params: params}} <- ValueParser.parse_fields(entity, params: :value),
         do: {:ok, params}
  end

  defp choice_options(options) do
    reduce(options, fn option ->
      with {:ok, %{condition: condition, params: params}} <-
             ValueParser.parse_fields(option, condition: :value, params: :value),
           {:ok, call} <- call(option, params) do
        {:ok, {option.name, condition, call}}
      end
    end)
  end

  defp choice_fallback(nil),
    do:
      {:error,
       Error.validation_error("Choice fallback is required", %{reason: :fallback_required})}

  defp choice_fallback(fallback), do: call(fallback)

  defp parallel_actions(actions) do
    reduce(actions, fn action ->
      with {:ok, call} <- call(action), do: {:ok, {action.name, call}}
    end)
  end

  defp optional_value(nil, default), do: {:ok, default}
  defp optional_value(value, _default), do: ValueParser.parse(value)

  defp wait_clauses(clauses) do
    reduce(clauses, fn
      %Forms.Wait.Selection.Await{} = entity ->
        with {:ok, %{match: match}} <- ValueParser.parse_fields(entity, match: :value),
             do: {:ok, {:event, entity.name, entity.event, match}}

      %Forms.Wait.Selection.Timer{} = entity ->
        {:ok, {:timer, entity.name, entity.after_ms}}
    end)
  end

  defp reduce(values, function) do
    values
    |> Enum.reduce_while({:ok, []}, fn value, {:ok, result} ->
      case function.(value) do
        {:ok, value} -> {:cont, {:ok, [value | result]}}
        {:error, error} -> {:halt, {:error, error}}
      end
    end)
    |> case do
      {:ok, result} -> {:ok, Enum.reverse(result)}
      error -> error
    end
  end
end

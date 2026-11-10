defmodule Jido.Flow.DSL.Lowerer do
  @moduledoc false

  alias Jido.Flow.{Component, Definition}
  alias Jido.Expr
  alias Jido.Error
  alias Jido.Flow.Ref

  @maximum_iterations Jido.Flow.Component.maximum_iterations()

  alias Jido.Flow.DSL.{
    Choice,
    ChoiceOption,
    Handoff,
    Invoke,
    ValueParser,
    Iterate,
    MapNode,
    Otherwise,
    Output,
    Parallel,
    ParallelAction,
    Reduce,
    SourceMap,
    Step
  }

  @doc "Lowers Spark entities into canonical Flow attributes and source locations."
  @spec lower(module(), map(), String.t()) ::
          {:ok, map(), map()} | {:error, Exception.t()}
  def lower(module, config, file) do
    entities = Spark.Dsl.Extension.get_entities(module, [:flow])

    with {:ok, entities, output_entity} <- split_output(entities),
         {:ok, components, sources} <- lower_components(entities, file),
         {:ok, output} <- lower_output(output_entity) do
      sources = SourceMap.put_entity(sources, output_entity, :output, file)

      definition_config = Map.take(config, [:name, :description, :schema, :output_schema])

      case Definition.diagnose_body(definition_config, components, output) do
        {:ok, attrs} ->
          {:ok, attrs, sources}

        {:error, [issue | _rest]} ->
          {:error, SourceMap.attach_issue(issue, sources, components)}
      end
    end
  end

  defp lower_components(entities, file) do
    entities
    |> Enum.with_index()
    |> Enum.reduce_while({:ok, [], %{}}, fn {entity, index}, {:ok, components, sources} ->
      case lower_entity(entity) do
        {:ok, component} ->
          sources = SourceMap.put_entity(sources, entity, index, file)
          {:cont, {:ok, [component | components], sources}}

        {:error, error} ->
          {:halt, {:error, SourceMap.attach_entity(error, entity)}}
      end
    end)
    |> case do
      {:ok, components, sources} -> {:ok, Enum.reverse(components), sources}
      {:error, error} -> {:error, error}
    end
  end

  defp lower_entity(%Jido.Flow.DSL.Timer{} = timer),
    do: component(timer, :timer, after_ms: timer.after_ms)

  defp lower_entity(%Jido.Flow.DSL.Await{} = wait) do
    with {:ok, %{match: match}} <- ValueParser.parse_fields(wait, match: :value),
         do: component(wait, :await, event: wait.event, match: match)
  end

  defp lower_entity(%Jido.Flow.DSL.Selection{} = selection) do
    with {:ok, options} <-
           Component.sequence(selection.options, fn
             %Jido.Flow.DSL.TimerOption{} = timer ->
               {:ok, %{kind: :timer, name: timer.name, after_ms: timer.after_ms}}

             %Jido.Flow.DSL.AwaitOption{} = wait ->
               with {:ok, %{match: match}} <- ValueParser.parse_fields(wait, match: :value),
                    do: {:ok, %{kind: :await, name: wait.name, event: wait.event, match: match}}
           end),
         do: component(selection, :selection, options: options)
  end

  defp lower_entity(%Step{} = step) do
    with {:ok, %{params: params}} <- ValueParser.parse_fields(step, params: :value) do
      step_component(step, params)
    end
  end

  defp lower_entity(%Choice{} = choice) do
    with {:ok, options} <- lower_choice_options(choice.options),
         {:ok, fallback} <- lower_fallback(choice.fallback) do
      component(choice, :choice, options: options, fallback: fallback)
    end
  end

  defp lower_entity(%MapNode{} = map) do
    with {:ok, %{collection: collection, params: params}} <-
           ValueParser.parse_fields(map, collection: :value, params: :value) do
      component(map, :map,
        collection: collection,
        action: map.action,
        params: params,
        on_error: map.on_error
      )
    end
  end

  defp lower_entity(%Parallel{} = parallel) do
    with {:ok, actions} <- lower_parallel_actions(parallel.actions) do
      component(parallel, :parallel, actions: actions, on_error: parallel.on_error)
    end
  end

  defp lower_entity(%Reduce{} = reduce) do
    with {:ok, %{collection: collection, initial: initial, params: params}} <-
           ValueParser.parse_fields(reduce, collection: :value, initial: :value, params: :value) do
      component(reduce, :reduce,
        collection: collection,
        initial: initial,
        action: reduce.action,
        params: params
      )
    end
  end

  defp lower_entity(%Iterate{} = iterate) do
    with {:ok, state} <- lower_iterate_state(iterate.state),
         {:ok, %{params: params, update: update, while: condition}} <-
           ValueParser.parse_fields(iterate,
             params: :value,
             update: {:value, Ref.body_result()},
             while: {:condition, nil}
           ),
         {:ok, completion, max_iterations} <-
           normalize_termination(iterate, condition) do
      component(iterate, :iterate,
        action: iterate.action,
        params: params,
        state: Map.put(state, :update, update),
        completion: completion,
        max_iterations: max_iterations
      )
    end
  end

  defp lower_entity(%Invoke{} = invoke) do
    with {:ok, %{params: params}} <- ValueParser.parse_fields(invoke, params: :value) do
      component(invoke, :invoke,
        decision: invoke.decision,
        expander: invoke.expander,
        params: params
      )
    end
  end

  defp lower_entity(%Handoff{} = handoff) do
    with {:ok, %{params: params}} <- ValueParser.parse_fields(handoff, params: :value) do
      component(handoff, :handoff,
        selector: handoff.selector,
        params: params
      )
    end
  end

  defp lower_output(nil), do: {:error, Error.validation_error("Flow output is required")}

  defp lower_output(%Output{} = output) do
    with {:ok, %{value: value}} <- ValueParser.parse_fields(output, value: :value) do
      {:ok, value}
    end
  end

  defp step_component(step, params) do
    with {:module, _module} <- Code.ensure_compiled(step.action),
         {:ok, kind} <- Jido.Instruction.target_kind(step.action) do
      if kind == :action,
        do: component(step, :step, action: step.action, params: params),
        else: component(step, :subflow, flow: step.action, params: params)
    else
      {:error, error} when is_exception(error) ->
        details = error |> Map.get(:details, %{}) |> Map.put(:cause, error.__struct__)
        {:error, Error.validation_error(Exception.message(error), details)}

      {:error, reason} ->
        {:error,
         Error.validation_error("step action module could not be compiled", %{
           action: step.action,
           reason: reason
         })}
    end
  end

  defp lower_choice_options([]) do
    {:error, Error.validation_error("choice must declare at least one option")}
  end

  defp lower_choice_options(options) do
    options
    |> Enum.reduce_while({:ok, []}, fn %ChoiceOption{} = option, {:ok, lowered} ->
      with {:ok, %{condition: condition, params: params}} <-
             ValueParser.parse_fields(option, condition: :condition, params: :value) do
        value = %{
          name: option.name,
          condition: condition,
          action: option.action,
          params: params
        }

        {:cont, {:ok, [value | lowered]}}
      else
        {:error, error} -> {:halt, {:error, error}}
      end
    end)
    |> reverse_ok()
  end

  defp lower_fallback(%Otherwise{} = fallback) do
    with {:ok, %{params: params}} <- ValueParser.parse_fields(fallback, params: :value) do
      {:ok, %{action: fallback.action, params: params}}
    end
  end

  defp lower_fallback(nil), do: {:error, Error.validation_error("choice must declare otherwise")}

  defp lower_parallel_actions([]) do
    {:error, Error.validation_error("parallel must declare at least one Action")}
  end

  defp lower_parallel_actions(actions) do
    actions
    |> Enum.reduce_while({:ok, []}, fn %ParallelAction{} = action, {:ok, lowered} ->
      case ValueParser.parse_fields(action, params: :value) do
        {:ok, %{params: params}} ->
          value = %{name: action.name, action: action.action, params: params}
          {:cont, {:ok, [value | lowered]}}

        {:error, error} ->
          {:halt, {:error, SourceMap.attach_entity(error, action)}}
      end
    end)
    |> reverse_ok()
  end

  defp lower_iterate_state(nil) do
    {:error, Error.validation_error("iterate must declare one state")}
  end

  defp lower_iterate_state(state) do
    with {:ok, %{initial: initial}} <- ValueParser.parse_fields(state, initial: :value) do
      {:ok, %{schema: state.schema, initial: initial}}
    end
  end

  defp normalize_termination(iterate, while_condition) do
    case {while_condition, iterate.repeat, iterate.max_iterations} do
      {condition, nil, maximum}
      when not is_nil(condition) and is_integer(maximum) and maximum in 1..@maximum_iterations ->
        {:ok, Expr.new!(:not, [condition]), maximum}

      {nil, count, nil} when is_integer(count) and count in 1..@maximum_iterations ->
        {:ok, Expr.new!(:>=, [Ref.iteration_index(), count]), count}

      {condition, nil, _maximum} when not is_nil(condition) ->
        {:error, Error.validation_error("iterate max_iterations must be an integer from 1 to 10000")}

      {nil, count, nil} when not is_nil(count) ->
        {:error, Error.validation_error("iterate repeat must be an integer from 1 to 10000")}

      {nil, _count, maximum} when not is_nil(maximum) ->
        {:error, Error.validation_error("iterate repeat must not set max_iterations")}

      _other ->
        {:error, Error.validation_error("iterate requires exactly one of while or repeat")}
    end
  end

  defp split_output(entities) do
    case Enum.split_while(entities, &(not match?(%Output{}, &1))) do
      {components, []} ->
        {:ok, components, nil}

      {components, [output]} ->
        {:ok, components, output}

      {_components, [output | _rest]} ->
        error = Error.validation_error("output must be the final Flow declaration")
        {:error, SourceMap.attach_entity(error, output)}
    end
  end

  defp reverse_ok({:ok, values}), do: {:ok, Enum.reverse(values)}
  defp reverse_ok({:error, error}), do: {:error, error}

  defp component(entity, kind, fields) do
    attrs = entity |> Map.take([:name, :needs, :meta]) |> Map.merge(Map.new(fields))
    {:ok, Component.authoring(Map.put(attrs, :kind, kind))}
  end
end

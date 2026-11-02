defmodule Jido.Flow.Codec.Forms do
  @moduledoc false

  alias Jido.Authoring.Registry
  alias Jido.Flow.Error
  alias Jido.Flow.Codec.{Data, Limits, Value}
  alias Jido.Flow.Form.{Choice, Invoke, Iterate, Parallel, Reduce, Wait}
  alias Jido.Flow.Form.Map, as: MapForm

  @doc false
  @spec encode(Jido.Flow.Form.t(), Registry.t()) ::
          {:ok, {String.t(), map()}} | {:error, Exception.t()}
  def encode(%MapForm{} = form, registry) do
    with {:ok, collection} <- Value.encode_expression(form.collection, registry, 0),
         {:ok, call} <- Data.encode_call(form.call, registry) do
      {:ok,
       {"map",
        %{
          "collection" => collection,
          "call" => call,
          "on_error" => Atom.to_string(form.on_error)
        }}}
    end
  end

  def encode(%Reduce{} = form, registry) do
    with {:ok, collection} <- Value.encode_expression(form.collection, registry, 0),
         {:ok, initial} <- Value.encode_expression(form.initial, registry, 0),
         {:ok, call} <- Data.encode_call(form.call, registry) do
      {:ok, {"reduce", %{"collection" => collection, "initial" => initial, "call" => call}}}
    end
  end

  def encode(%Choice{} = form, registry) do
    with :ok <- Limits.size(form.options),
         {:ok, options} <- encode_choice_options(form.options, registry),
         {:ok, fallback} <- Data.encode_call(form.fallback, registry) do
      {:ok, {"choice", %{"options" => options, "fallback" => fallback}}}
    end
  end

  def encode(%Parallel{} = form, registry) do
    with :ok <- Limits.size(form.actions),
         {:ok, actions} <- encode_parallel_actions(form.actions, registry) do
      {:ok, {"parallel", %{"actions" => actions, "on_error" => Atom.to_string(form.on_error)}}}
    end
  end

  def encode(%Iterate{} = form, registry) do
    with {:ok, schema} <- Registry.encode_reference(registry, :schema, form.state_schema),
         {:ok, initial} <- Value.encode_expression(form.initial, registry, 0),
         {:ok, call} <- Data.encode_call(form.call, registry),
         {:ok, update} <- Value.encode_expression(form.update, registry, 0),
         {:ok, mode} <- encode_iterate_mode(form.mode, registry) do
      {:ok,
       {"iterate",
        %{
          "state_schema" => schema,
          "initial" => initial,
          "call" => call,
          "update" => update,
          "mode" => mode
        }}}
    end
  end

  def encode(%Invoke{} = call, registry) do
    with {:ok, target} <- Value.encode_expression(call.target, registry, 0),
         {:ok, params} <- Value.encode_expression(call.params, registry, 0),
         {:ok, meta} <- Value.encode_data(call.metadata, registry, 0),
         {:ok, targets} <- encode_invoke_targets(call.targets, registry) do
      {:ok,
       {"invoke",
        %{
          "target" => target,
          "targets" => targets,
          "params" => params,
          "meta" => meta,
          "policy" => Data.encode_policy(call.policy),
          "on_error" => Atom.to_string(call.on_error)
        }}}
    end
  end

  def encode(%Wait{} = form, registry) do
    with :ok <- Limits.size(form.clauses),
         {:ok, clauses} <- encode_wait_clauses(form.clauses, registry) do
      {:ok, {"wait", %{"clauses" => clauses}}}
    end
  end

  def encode(form, _registry) do
    {:error,
     Error.validation_error("Flow form is not supported", %{reason: :form_codec, value: form})}
  end

  @doc false
  @spec decode(String.t(), term(), Registry.t(), list()) ::
          {:ok, map()} | {:error, [Exception.t()]}
  def decode("map", record, registry, path) when is_map(record) and not is_struct(record) do
    with :ok <- Data.exact_fields(record, ["collection", "call", "on_error"], path),
         {:ok, collection_record} <- Data.required(record, "collection", path),
         {:ok, collection} <-
           Data.decode_value(collection_record, registry, path ++ ["collection"]),
         {:ok, call_record} <- Data.required(record, "call", path),
         {:ok, call} <- Data.decode_call(call_record, registry, path ++ ["call"]),
         {:ok, policy_record} <- Data.required(record, "on_error", path),
         {:ok, policy} <- Data.decode_on_error(policy_record, path ++ ["on_error"], "Map") do
      {:ok, %{type: :map, collection: collection, call: call, on_error: policy}}
    else
      error -> decode_error(error, path)
    end
  end

  def decode("reduce", record, registry, path) when is_map(record) and not is_struct(record) do
    with :ok <- Data.exact_fields(record, ["collection", "initial", "call"], path),
         {:ok, collection_record} <- Data.required(record, "collection", path),
         {:ok, collection} <-
           Data.decode_value(collection_record, registry, path ++ ["collection"]),
         {:ok, initial_record} <- Data.required(record, "initial", path),
         {:ok, initial} <- Data.decode_value(initial_record, registry, path ++ ["initial"]),
         {:ok, call_record} <- Data.required(record, "call", path),
         {:ok, call} <- Data.decode_call(call_record, registry, path ++ ["call"]) do
      {:ok, %{type: :reduce, collection: collection, initial: initial, call: call}}
    else
      error -> decode_error(error, path)
    end
  end

  def decode("choice", record, registry, path) when is_map(record) and not is_struct(record) do
    with :ok <- Data.exact_fields(record, ["options", "fallback"], path),
         {:ok, options_record} <- Data.required(record, "options", path),
         {:ok, options} <- decode_choice_options(options_record, registry, path ++ ["options"]),
         {:ok, fallback_record} <- Data.required(record, "fallback", path),
         {:ok, fallback} <- Data.decode_call(fallback_record, registry, path ++ ["fallback"]) do
      {:ok, %{type: :choice, options: options, fallback: fallback}}
    else
      error -> decode_error(error, path)
    end
  end

  def decode("parallel", record, registry, path) when is_map(record) and not is_struct(record) do
    with :ok <- Data.exact_fields(record, ["actions", "on_error"], path),
         {:ok, actions_record} <- Data.required(record, "actions", path),
         {:ok, actions} <- decode_parallel_actions(actions_record, registry, path ++ ["actions"]),
         {:ok, policy_record} <- Data.required(record, "on_error", path),
         {:ok, policy} <- Data.decode_on_error(policy_record, path ++ ["on_error"], "Parallel") do
      {:ok, %{type: :parallel, actions: actions, on_error: policy}}
    else
      error -> decode_error(error, path)
    end
  end

  def decode("iterate", record, registry, path) when is_map(record) and not is_struct(record) do
    fields = ["state_schema", "initial", "call", "update", "mode"]

    with :ok <- Data.exact_fields(record, fields, path),
         {:ok, schema_record} <- Data.required(record, "state_schema", path),
         {:ok, schema} <- decode_schema(schema_record, registry, path ++ ["state_schema"]),
         {:ok, initial_record} <- Data.required(record, "initial", path),
         {:ok, initial} <- Data.decode_value(initial_record, registry, path ++ ["initial"]),
         {:ok, call_record} <- Data.required(record, "call", path),
         {:ok, call} <- Data.decode_call(call_record, registry, path ++ ["call"]),
         {:ok, update_record} <- Data.required(record, "update", path),
         {:ok, update} <- Data.decode_value(update_record, registry, path ++ ["update"]),
         {:ok, mode_record} <- Data.required(record, "mode", path),
         {:ok, mode_attrs} <- decode_iterate_mode(mode_record, registry, path ++ ["mode"]) do
      {:ok,
       Map.merge(mode_attrs, %{
         type: :iterate,
         state_schema: schema,
         initial: initial,
         call: call,
         update: update
       })}
    else
      error -> decode_error(error, path)
    end
  end

  def decode("invoke", record, registry, path) when is_map(record) and not is_struct(record) do
    fields = ["target", "targets", "params", "meta", "policy", "on_error"]

    with :ok <- Data.exact_fields(record, fields, path),
         {:ok, target_record} <- Data.required(record, "target", path),
         {:ok, target} <- Data.decode_value(target_record, registry, path ++ ["target"]),
         {:ok, targets_record} <- Data.required(record, "targets", path),
         {:ok, targets} <- decode_invoke_targets(targets_record, registry, path ++ ["targets"]),
         {:ok, params_record} <- Data.required(record, "params", path),
         {:ok, params} <- Data.decode_value(params_record, registry, path ++ ["params"]),
         {:ok, meta_record} <- Data.required(record, "meta", path),
         {:ok, meta} <- Data.decode_value(meta_record, registry, path ++ ["meta"], :data),
         {:ok, policy} <- Data.required(record, "policy", path),
         {:ok, on_error_record} <- Data.required(record, "on_error", path),
         {:ok, on_error} <- Data.decode_on_error(on_error_record, path ++ ["on_error"], "Invoke") do
      {:ok,
       %{
         type: :invoke,
         target: target,
         targets: targets,
         params: params,
         meta: meta,
         policy: policy,
         on_error: on_error
       }}
    else
      error -> decode_error(error, path)
    end
  end

  def decode("wait", record, registry, path) when is_map(record) and not is_struct(record) do
    with :ok <- Data.exact_fields(record, ["clauses"], path),
         {:ok, clauses_record} <- Data.required(record, "clauses", path),
         {:ok, clauses} <- decode_wait_clauses(clauses_record, registry, path ++ ["clauses"]) do
      {:ok, %{type: :wait, clauses: clauses}}
    else
      error -> decode_error(error, path)
    end
  end

  def decode(type, _record, _registry, path)
      when type in ["map", "reduce", "choice", "parallel", "iterate", "invoke", "wait"],
      do:
        Data.failure(
          "stored #{String.capitalize(type)} form must be a map",
          path,
          String.to_atom(type)
        )

  def decode(_type, _record, _registry, path),
    do: Data.failure("stored Flow form type is not supported", path, :form)

  defp encode_choice_options(options, registry) do
    encode_list(options, "options", fn {name, condition, call} ->
      with {:ok, condition} <- Value.encode_expression(condition, registry, 0),
           {:ok, call} <- Data.encode_call(call, registry),
           do: {:ok, [name, condition, call]}
    end)
  end

  defp decode_choice_options(options, registry, path) when is_list(options) do
    with false <- List.improper?(options),
         :ok <- Limits.size(options) do
      decode_list(options, path, fn
        [name, condition_record, call_record], item_path when is_binary(name) ->
          with {:ok, condition} <- Data.decode_value(condition_record, registry, item_path ++ [1]),
               {:ok, call} <- Data.decode_call(call_record, registry, item_path ++ [2]),
               do: {:ok, {name, condition, call}}

        _option, item_path ->
          Data.failure("stored Choice option must be [name, condition, call]", item_path, :option)
      end)
    else
      true -> Data.failure("stored Choice options must be a proper list", path, :options)
      {:error, error} -> {:error, [Error.prefix_path(error, path)]}
    end
  end

  defp decode_choice_options(_options, _registry, path),
    do: Data.failure("stored Choice options must be a list", path, :options)

  defp encode_parallel_actions(actions, registry) do
    encode_list(actions, "actions", fn {name, call} ->
      with {:ok, call} <- Data.encode_call(call, registry), do: {:ok, [name, call]}
    end)
  end

  defp decode_parallel_actions(actions, registry, path) when is_list(actions) do
    with false <- List.improper?(actions),
         :ok <- Limits.size(actions) do
      decode_list(actions, path, fn
        [name, call_record], item_path when is_binary(name) ->
          with {:ok, call} <- Data.decode_call(call_record, registry, item_path ++ [1]),
               do: {:ok, {name, call}}

        _action, item_path ->
          Data.failure("stored Parallel Action must be [name, call]", item_path, :action)
      end)
    else
      true -> Data.failure("stored Parallel actions must be a proper list", path, :actions)
      {:error, error} -> {:error, [Error.prefix_path(error, path)]}
    end
  end

  defp decode_parallel_actions(_actions, _registry, path),
    do: Data.failure("stored Parallel actions must be a list", path, :actions)

  defp encode_iterate_mode({:repeat, count}, _registry), do: {:ok, ["repeat", count]}

  defp encode_iterate_mode({:while, condition, maximum}, registry) do
    with {:ok, condition} <- Value.encode_expression(condition, registry, 0),
         do: {:ok, ["while", condition, maximum]}
  end

  defp decode_iterate_mode(["repeat", count], _registry, _path), do: {:ok, %{repeat: count}}

  defp decode_iterate_mode(["while", condition_record, maximum], registry, path) do
    with {:ok, condition} <- Data.decode_value(condition_record, registry, path ++ [1]),
         do: {:ok, %{while: condition, max_iterations: maximum}}
  end

  defp decode_iterate_mode(_record, _registry, path),
    do: Data.failure("stored Iterate mode is invalid", path, :mode)

  defp decode_schema(record, registry, path) do
    case Registry.decode_reference(registry, record, :schema) do
      {:ok, schema} -> {:ok, schema}
      {:error, error} -> {:error, [Error.prefix_path(error, path)]}
    end
  end

  defp encode_invoke_targets(targets, registry) do
    with :ok <- Limits.size(targets) do
      targets
      |> Enum.sort_by(&elem(&1, 0))
      |> Enum.reduce_while({:ok, []}, fn {id, target}, {:ok, encoded} ->
        case Registry.encode_reference(registry, [:action, :flow], target) do
          {:ok, reference} -> {:cont, {:ok, [[id, reference] | encoded]}}
          {:error, error} -> {:halt, {:error, error}}
        end
      end)
      |> reverse_result()
    end
  end

  defp decode_invoke_targets(records, registry, path) when is_list(records) do
    with false <- List.improper?(records),
         :ok <- Limits.size(records) do
      records
      |> Enum.with_index()
      |> Enum.reduce_while({:ok, %{}}, fn {record, index}, {:ok, targets} ->
        item_path = path ++ [index]

        case record do
          [id, reference] when is_binary(id) and not is_map_key(targets, id) ->
            case Data.decode_reference(reference, [:action, :flow], registry, item_path ++ [1]) do
              {:ok, target} -> {:cont, {:ok, Map.put(targets, id, target)}}
              {:error, errors} -> {:halt, {:error, errors}}
            end

          [id, _reference] when is_binary(id) ->
            {:halt,
             Data.failure(
               "stored Invoke contains a duplicate target ID",
               item_path ++ [0],
               :duplicate_invoke_target
             )}

          _other ->
            {:halt,
             Data.failure("stored Invoke target must be [id, reference]", item_path, :target)}
        end
      end)
    else
      true -> Data.failure("stored Invoke targets must be a proper list", path, :targets)
      {:error, error} -> {:error, [Error.prefix_path(error, path)]}
    end
  end

  defp decode_invoke_targets(_records, _registry, path),
    do: Data.failure("stored Invoke targets must be a list", path, :targets)

  defp encode_wait_clauses(clauses, registry) do
    encode_list(clauses, "clauses", fn
      {:event, name, event, match} ->
        with {:ok, match} <- Value.encode_expression(match, registry, 0),
             do: {:ok, ["event", name, event, match]}

      {:timer, name, delay} ->
        {:ok, ["timer", name, delay]}
    end)
  end

  defp decode_wait_clauses(clauses, registry, path) when is_list(clauses) do
    with false <- List.improper?(clauses),
         :ok <- Limits.size(clauses) do
      decode_list(clauses, path, fn
        ["event", name, event, match_record], item_path ->
          with {:ok, match} <- Data.decode_value(match_record, registry, item_path ++ [3]),
               do: {:ok, {:event, name, event, match}}

        ["timer", name, delay], _item_path ->
          {:ok, {:timer, name, delay}}

        _clause, item_path ->
          Data.failure("stored Wait clause is invalid", item_path, :clause)
      end)
    else
      true -> Data.failure("stored Wait clauses must be a proper list", path, :clauses)
      {:error, error} -> {:error, [Error.prefix_path(error, path)]}
    end
  end

  defp decode_wait_clauses(_clauses, _registry, path),
    do: Data.failure("stored Wait clauses must be a list", path, :clauses)

  defp encode_list(values, field, function) do
    values
    |> Enum.with_index()
    |> Enum.reduce_while({:ok, []}, fn {value, index}, {:ok, result} ->
      case function.(value) do
        {:ok, encoded} -> {:cont, {:ok, [encoded | result]}}
        {:error, error} -> {:halt, {:error, Error.prefix_path(error, [field, index])}}
      end
    end)
    |> reverse_result()
  end

  defp decode_list(values, path, function) do
    values
    |> Enum.with_index()
    |> Enum.reduce_while({:ok, []}, fn {value, index}, {:ok, result} ->
      case function.(value, path ++ [index]) do
        {:ok, decoded} -> {:cont, {:ok, [decoded | result]}}
        {:error, errors} -> {:halt, {:error, errors}}
      end
    end)
    |> reverse_result()
  end

  defp reverse_result({:ok, values}), do: {:ok, Enum.reverse(values)}
  defp reverse_result(error), do: error

  defp decode_error({:error, errors}, _path) when is_list(errors), do: {:error, errors}
  defp decode_error({:error, error}, path), do: {:error, [Error.prefix_path(error, path)]}
end

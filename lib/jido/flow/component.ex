defmodule Jido.Flow.Component do
  @moduledoc false

  alias Jido.Codec.Config
  alias Jido.Error
  alias Jido.Flow.{FieldError, Value}

  @common [name: :name, needs: :needs, meta: :meta]
  @fields %{
    wait: [options: :wait_options],
    call: [call: {:call, [:action, :flow], :flow}],
    choice: [options: :options, fallback: {:call, [:action], :flow}],
    map: [
      collection: {:value, :map_collection},
      call: {:call, [:action], :map_params},
      on_error: :on_error
    ],
    parallel: [actions: :parallel_actions, on_error: :on_error],
    reduce: [
      collection: {:value, :reduce_collection},
      initial: {:value, :reduce_initial},
      call: {:call, [:action], :reduce_params}
    ],
    iterate: [
      call: {:call, [:action], :iterate_params},
      state: :state,
      completion: {:condition, :iterate_completion},
      max_iterations: :maximum_iterations
    ],
    invoke: [decision: {:call, [:action], :flow}, expander: {:target, [:action]}],
    handoff: [selector: {:call, [:action], :flow}]
  }
  @wait_option [name: :name, event: :event, match: {:value, :flow}, after_ms: :delay]
  @option [name: :name, condition: {:condition, :flow}, call: {:call, [:action], :flow}]
  @parallel_action [name: :name, call: {:call, [:action], :flow}]
  @state [schema: :schema, initial: {:value, :iterate_initial}, update: {:value, :iterate_update}]
  @maximum_iterations 10_000

  @type call :: %{kind: Jido.Instruction.kind(), target: module(), params: Value.t()}
  @type target :: %{kind: Jido.Instruction.kind(), target: module()}
  @type mode :: :authoring | :lowered | :canonical

  @doc false
  @spec maximum_iterations() :: pos_integer()
  def maximum_iterations, do: @maximum_iterations

  @doc false
  @spec fields(atom()) :: keyword() | nil
  def fields(kind), do: Map.get(@fields, kind)

  @doc false
  @spec common_fields() :: keyword()
  def common_fields, do: @common

  @doc false
  @spec option_fields() :: keyword()
  def option_fields, do: @option

  @doc false
  @spec parallel_action_fields() :: keyword()
  def parallel_action_fields, do: @parallel_action

  @doc false
  @spec wait_option_fields() :: keyword()
  def wait_option_fields, do: @wait_option

  @doc false
  @spec state_fields() :: keyword()
  def state_fields, do: @state

  @doc false
  @spec diagnose(term(), mode()) :: {:ok, {String.t(), map()}} | {:error, [Exception.t()]}
  def diagnose(attrs, mode \\ :authoring)

  def diagnose(%FieldError{errors: errors}, _mode), do: {:error, errors}

  def diagnose(%{} = attrs, :authoring) when not is_struct(attrs),
    do: diagnose(authoring(attrs), :lowered)

  def diagnose(%{} = attrs, mode) when not is_struct(attrs) do
    case fields(Map.get(attrs, :kind)) do
      nil ->
        {:error, [Error.validation_error("expected a supported Flow component kind", %{value: attrs})]}

      fields ->
        case record(attrs, @common ++ fields, mode, [:kind]) do
          {:ok, values} ->
            {:ok, {values.name, values |> Map.delete(:name) |> Map.put(:kind, attrs.kind)}}

          error ->
            error
        end
    end
  end

  def diagnose(value, _mode),
    do: {:error, [Error.validation_error("expected a Flow component map", %{value: value})]}

  defp option(attrs, mode), do: record(attrs, @option, mode)

  defp state(attrs, mode), do: record(attrs, @state, mode)

  @doc false
  @spec authoring(map()) :: map() | FieldError.t()
  def authoring(%{kind: kind} = attrs) when kind in [:timer, :await] do
    case wait_option(Map.take(attrs, [:kind, :name, :event, :match, :after_ms])) do
      %FieldError{} = error ->
        error

      option ->
        attrs
        |> Map.drop([:event, :match, :after_ms])
        |> Map.put(:kind, :wait)
        |> Map.put(:options, [option])
    end
  end

  def authoring(%{kind: :selection, options: options} = attrs) do
    options =
      if is_list(options) and not List.improper?(options),
        do: Enum.map(options, &wait_option/1),
        else: options

    attrs |> Map.put(:kind, :wait) |> Map.put(:options, options)
  end

  def authoring(%{kind: :call}) do
    %FieldError{
      errors: [
        Error.validation_error("data authoring uses :step or :subflow for a call", %{
          path: [:kind]
        })
      ]
    }
  end

  def authoring(%{call: _}), do: unknown_call_field()

  def authoring(%{kind: kind} = attrs) when kind in [:step, :subflow] do
    target_field = if kind == :step, do: :action, else: :flow
    target_kind = if kind == :step, do: :action, else: :flow

    attrs
    |> Map.drop([target_field, :params])
    |> Map.put(:kind, :call)
    |> Map.put(:call, %{
      kind: target_kind,
      target: Map.get(attrs, target_field),
      params: Map.get(attrs, :params, %{})
    })
  end

  def authoring(%{kind: kind} = attrs) when kind in [:map, :reduce, :iterate] do
    authoring_call(attrs)
  end

  def authoring(%{kind: :parallel} = attrs) do
    Map.update(attrs, :actions, nil, fn actions ->
      if is_list(actions) and not List.improper?(actions),
        do: Enum.map(actions, &authoring_call/1),
        else: actions
    end)
  end

  def authoring(%{kind: :choice} = attrs) do
    attrs
    |> Map.update(:options, nil, fn options ->
      if is_list(options) and not List.improper?(options),
        do: Enum.map(options, &authoring_call/1),
        else: options
    end)
    |> Map.update(:fallback, nil, &authoring_target_call/1)
  end

  def authoring(%{kind: :invoke} = attrs) do
    attrs
    |> Map.delete(:params)
    |> Map.put(:decision, %{
      kind: :action,
      target: Map.get(attrs, :decision),
      params: Map.get(attrs, :params, %{})
    })
    |> Map.put(:expander, %{kind: :action, target: Map.get(attrs, :expander)})
  end

  def authoring(%{kind: :handoff} = attrs) do
    attrs
    |> Map.delete(:params)
    |> Map.put(:selector, %{
      kind: :action,
      target: Map.get(attrs, :selector),
      params: Map.get(attrs, :params, %{})
    })
  end

  def authoring(attrs), do: attrs

  defp wait_option(%{kind: kind} = attrs) when kind in [:timer, :await] do
    valid? =
      case kind do
        :timer ->
          Map.has_key?(attrs, :after_ms) and not Map.has_key?(attrs, :event) and
            not Map.has_key?(attrs, :match)

        :await ->
          Map.has_key?(attrs, :event) and not Map.has_key?(attrs, :after_ms)
      end

    if valid?,
      do:
        attrs
        |> Map.delete(:kind)
        |> Map.put_new(:event, nil)
        |> Map.put_new(:match, %{})
        |> Map.put_new(:after_ms, nil),
      else: %FieldError{
        errors: [
          Error.validation_error("wait fields do not match the declared kind", %{kind: kind})
        ]
      }
  end

  defp wait_option(other), do: other

  defp authoring_call(%{call: _}), do: unknown_call_field()

  defp authoring_call(%{} = attrs) when not is_struct(attrs) do
    attrs
    |> Map.drop([:action, :params])
    |> Map.put(:call, %{
      kind: :action,
      target: Map.get(attrs, :action),
      params: Map.get(attrs, :params, %{})
    })
  end

  defp authoring_call(attrs), do: attrs

  defp authoring_target_call(%{} = attrs) when not is_struct(attrs) do
    case unknown_fields(attrs, [:action, :params]) do
      [] ->
        attrs
        |> Map.delete(:action)
        |> Map.put(:kind, :action)
        |> Map.put(:target, Map.get(attrs, :action))

      errors ->
        %FieldError{errors: errors}
    end
  end

  defp authoring_target_call(attrs), do: attrs

  defp unknown_call_field,
    do: %FieldError{errors: unknown_fields(%{call: nil}, [])}

  defp record(attrs, fields, mode, extra \\ [])

  defp record(%FieldError{errors: errors}, _fields, _mode, _extra), do: {:error, errors}

  defp record(%{} = attrs, fields, mode, extra) when not is_struct(attrs) do
    allowed = Keyword.keys(fields) ++ extra

    errors = unknown_fields(attrs, allowed)

    {values, errors} =
      Enum.reduce(fields, {%{}, errors}, fn {field, type}, {values, errors} ->
        value = Map.get(attrs, field, default(field, mode))
        value = if mode == :lowered and field == :params and is_nil(value), do: %{}, else: value

        case validate(type, value, mode) do
          {:ok, value} ->
            {Map.put(values, field, value), errors}

          {:error, nested} ->
            {values, errors ++ Enum.map(List.wrap(nested), &Error.prefix_path(&1, [field]))}
        end
      end)

    if errors == [], do: {:ok, values}, else: {:error, errors}
  end

  defp record(_attrs, _fields, _mode, _extra), do: failure("Flow field must be a map")

  defp unknown_fields(attrs, allowed) do
    attrs
    |> Map.keys()
    |> Enum.reject(&(&1 in allowed))
    |> Enum.sort_by(&:erlang.term_to_binary/1)
    |> Enum.map(fn key ->
      Error.validation_error("unknown Flow field: #{inspect(key)}", %{path: [key], key: key})
    end)
  end

  defp default(_field, :canonical), do: {:__missing_flow_field__}
  defp default(field, :lowered) when field in [:params, :meta], do: %{}
  defp default(:needs, :lowered), do: []
  defp default(:schema, :lowered), do: Jido.Joi.map()
  defp default(:on_error, :lowered), do: :fail_fast
  defp default(_field, :lowered), do: {:__missing_flow_field__}

  defp validate(_type, %FieldError{errors: errors}, _mode), do: {:error, errors}

  defp validate(_type, {:__missing_flow_field__}, _mode), do: failure("Flow field is required")

  defp validate(:name, value, :lowered) when is_atom(value) and not is_nil(value),
    do: validate(:name, Atom.to_string(value), :canonical)

  defp validate(:name, value, _mode) do
    case Config.validate_name(value) do
      :ok -> {:ok, value}
      {:error, message} -> failure(message)
    end
  end

  defp validate(:needs, nil, :lowered), do: {:ok, []}

  defp validate(:needs, values, mode) when is_list(values) do
    if List.improper?(values) do
      failure("component needs must be a proper list")
    else
      case sequence(values, fn value -> need_name(value, mode) end) do
        {:ok, names} ->
          case names -- Enum.uniq(names) do
            [] -> {:ok, names}
            [name | _] -> failure("component needs contains a duplicate", %{name: name})
          end

        error ->
          error
      end
    end
  end

  defp validate(:needs, _value, _mode), do: failure("component needs must be a list")
  defp validate(:meta, nil, :lowered), do: {:ok, %{}}
  defp validate(:meta, value, _mode), do: value_result(Value.validate_object(value), value)

  defp validate(:schema, value, mode) do
    case Config.schema(value, "iterate state schema") do
      {:ok, normalized} when mode == :canonical and normalized != value ->
        failure("Flow artifact contains non-canonical data", %{reason: :non_canonical})

      result ->
        result
    end
  end

  defp validate({:value, scope}, value, :lowered), do: Value.prepare(value, scope)

  defp validate({:value, scope}, value, :canonical),
    do: value_result(Value.validate(value, scope), value)

  defp validate({:params, _scope}, nil, :canonical),
    do: failure("Flow artifact contains non-canonical data", %{reason: :non_canonical})

  defp validate({:params, scope}, value, mode), do: validate({:value, scope}, value, mode)

  defp validate({:condition, scope}, value, mode)
       when is_boolean(value) or is_struct(value, Jido.Flow.Ref) or is_struct(value, Jido.Expr),
       do: validate({:value, scope}, value, mode)

  defp validate({:condition, _scope}, _value, _mode),
    do: failure("condition must be a Boolean, Flow reference, or Jido.Expr")

  defp validate({:target, kinds}, value, mode), do: target_record(value, kinds, mode)

  defp validate({:call, kinds, scope}, %{} = value, mode) when not is_struct(value) do
    case record(value, [kind: {:kind, kinds}, target: :module, params: {:params, scope}], mode) do
      {:ok, call} -> {:ok, call}
      error -> error
    end
  end

  defp validate({:call, _, _}, _value, _mode),
    do: failure("Flow call must be a kind, target, and params record")

  defp validate({:kind, kinds}, value, _mode) do
    if value in kinds,
      do: {:ok, value},
      else:
        failure("Flow call has the wrong target kind", %{
          expected: kinds,
          actual: value,
          reason: :invalid_target_kind
        })
  end

  defp validate(:module, value, _mode) when is_atom(value) and value not in [nil, true, false],
    do: {:ok, value}

  defp validate(:module, _value, _mode), do: failure("Flow target must be a module atom")

  defp validate(:on_error, value, _mode) when value in [:fail_fast, :collect_errors],
    do: {:ok, value}

  defp validate(:on_error, value, _mode),
    do: failure("on_error must be :fail_fast or :collect_errors", %{on_error: value})

  defp validate(:parallel_actions, values, mode) when is_list(values) do
    cond do
      values == [] ->
        failure("parallel must contain at least one Action")

      List.improper?(values) ->
        failure("parallel actions must be a proper list")

      true ->
        case sequence(values, &record(&1, @parallel_action, mode)) do
          {:ok, actions} ->
            case Enum.map(actions, & &1.name) -- Enum.uniq(Enum.map(actions, & &1.name)) do
              [] -> {:ok, actions}
              [name | _] -> failure("parallel Action names must be unique", %{name: name})
            end

          error ->
            error
        end
    end
  end

  defp validate(:parallel_actions, _value, _mode),
    do: failure("parallel actions must be a list")

  defp validate(:maximum_iterations, value, _mode)
       when is_integer(value) and value in 1..@maximum_iterations, do: {:ok, value}

  defp validate(:maximum_iterations, _value, _mode),
    do: failure("iterate max_iterations must be an integer from 1 to 10000")

  defp validate(:event, nil, _mode), do: {:ok, nil}

  defp validate(:event, value, _mode) when is_binary(value) and byte_size(value) > 0,
    do: {:ok, value}

  defp validate(:event, _value, _mode), do: failure("wait event must be a non-empty string")
  defp validate(:delay, nil, _mode), do: {:ok, nil}

  defp validate(:delay, value, _mode) when is_integer(value) and value >= 0,
    do: {:ok, value}

  defp validate(:delay, _value, _mode), do: failure("wait delay must be a non-negative integer")

  defp validate(:wait_options, values, mode) when is_list(values) do
    if values != [] and not List.improper?(values) do
      with {:ok, options} <- sequence(values, &record(&1, @wait_option, mode)) do
        valid? =
          Enum.all?(options, fn o ->
            (is_nil(o.event) and is_integer(o.after_ms) and o.match == %{}) or
              (is_binary(o.event) and is_nil(o.after_ms) and is_map(o.match))
          end)

        if valid? and length(Enum.uniq_by(options, & &1.name)) == length(options),
          do: {:ok, options},
          else: failure("wait options need unique names and exactly one timer or event")
      end
    else
      failure("wait options must be a non-empty proper list")
    end
  end

  defp validate(:wait_options, _value, _mode), do: failure("wait options must be a list")

  defp validate(:options, values, mode) when is_list(values) do
    cond do
      values == [] ->
        failure("choice must contain at least one option")

      List.improper?(values) ->
        failure("choice options must be a proper list")

      true ->
        case sequence(values, &option(&1, mode)) do
          {:ok, options} ->
            case Enum.map(options, & &1.name) -- Enum.uniq(Enum.map(options, & &1.name)) do
              [] -> {:ok, options}
              [name | _] -> failure("choice option names must be unique", %{name: name})
            end

          error ->
            error
        end
    end
  end

  defp validate(:options, _value, _mode), do: failure("choice options must be a list")
  defp validate(:state, value, mode), do: state(value, mode)

  defp target_record(value, kinds, mode),
    do: record(value, [kind: {:kind, kinds}, target: :module], mode)

  @doc false
  @spec sequence(list(), (term() -> {:ok, term()} | {:error, term()})) ::
          {:ok, list()} | {:error, [Exception.t()]}
  def sequence(values, validator) do
    {values, errors} =
      values
      |> Enum.with_index()
      |> Enum.reduce({[], []}, fn {value, index}, {values, errors} ->
        case validator.(value) do
          {:ok, value} ->
            {[value | values], errors}

          {:error, nested} ->
            {values,
             Enum.reduce(List.wrap(nested), errors, fn error, acc ->
               [Error.prefix_path(error, [index]) | acc]
             end)}
        end
      end)

    if errors == [], do: {:ok, Enum.reverse(values)}, else: {:error, Enum.reverse(errors)}
  end

  defp value_result(:ok, value), do: {:ok, value}
  defp value_result({:error, error}, _value), do: {:error, error}

  defp need_name(value, mode) do
    case validate(:name, value, mode) do
      {:ok, name} -> {:ok, name}
      {:error, _} -> failure("component needs must contain component names")
    end
  end

  defp failure(message, details \\ %{}), do: {:error, [Error.validation_error(message, details)]}
end

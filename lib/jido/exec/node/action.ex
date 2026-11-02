defmodule Jido.Exec.Node.Action do
  @moduledoc false

  use Runic.Workflow.SingleOutput, batch_parent: false

  alias Jido.Action.Error
  alias Jido.Exec.{Frame, Portable, Runtime, Validation, ValueResolver}
  alias Jido.Exec.Node.Loop
  alias Jido.Exec.Telemetry
  alias Jido.Instruction
  alias Runic.Identity
  alias Runic.Workflow.SingleOutput.{Context, Result}

  @enforce_keys [:id, :name, :hash, :instruction, :target_version, :inputs, :outputs]
  # `flow` holds the Flow component data for a Flow-created node. Caller
  # Instruction metadata stays an annotation with no execution meaning.
  defstruct [:id, :name, :hash, :instruction, :target_version, :inputs, :outputs, :flow]

  @type t :: %__MODULE__{
          id: term(),
          name: atom() | String.t(),
          hash: Identity.t(),
          instruction: Instruction.t(),
          target_version: term(),
          inputs: keyword(),
          outputs: keyword(),
          flow: map() | nil
        }

  @doc false
  @spec new(
          Instruction.t() | Jido.Flow.Component.target() | Jido.Flow.Component.call(),
          keyword()
        ) :: t()
  def new(instruction, opts \\ [])

  def new(%{kind: :action, target: target} = call, opts) when not is_struct(call) do
    flow = opts |> Keyword.fetch!(:flow) |> Map.put(:params, Map.get(call, :params))
    new(Instruction.new!(kind: :action, target: target), Keyword.put(opts, :flow, flow))
  end

  def new(%Instruction{kind: :action, target: action} = instruction, opts) do
    opts = Keyword.validate!(opts, [:id, :name, :flow, :target_version])

    case Instruction.validate_resolved(instruction) do
      :ok -> :ok
      {:error, error} -> raise error
    end

    name = Keyword.get_lazy(opts, :name, fn -> action_name(action) end)
    id = Keyword.get(opts, :id, name)
    target_version = Keyword.get_lazy(opts, :target_version, fn -> target_version(action) end)

    hash =
      Identity.digest(:component_definition, %{
        kind: "jido_action",
        version: 1,
        id: identity_value(id),
        target: Atom.to_string(action),
        target_version: target_version
      })

    %__MODULE__{
      id: id,
      name: name,
      hash: hash,
      instruction: instruction,
      target_version: target_version,
      inputs: ports(:input, action),
      outputs: ports(:output, action),
      flow: Keyword.get(opts, :flow)
    }
  end

  def new(%Instruction{} = instruction, _opts) do
    raise ArgumentError,
          "expected an Action Instruction, got: #{inspect(instruction.kind)}"
  end

  @impl Runic.Workflow.SingleOutput
  @doc false
  @spec run(t(), term(), Context.t()) :: Result.t()
  def run(%__MODULE__{} = node, input, %Context{} = context) do
    result =
      Telemetry.span(:action, Telemetry.action_metadata(node, context), fn ->
        execute(node, Jido.Exec.Fact.unwrap(input), context.runtime, context.input_metadata)
      end)

    case result do
      {:ok, value, effects} ->
        Jido.Exec.Fact.result(
          input,
          context,
          value,
          append_effects(Map.delete(context.input_metadata, :runic), effects)
        )

      {:error, error} ->
        Result.failure(error)
    end
  end

  defp append_effects(meta, effects) do
    jido = Map.get(meta, :jido, %{})
    prior = Map.get(jido, :effects, [])
    Map.put(meta, :jido, Map.put(jido, :effects, prior ++ effects))
  end

  @doc false
  @spec execute(t(), term(), map(), map()) :: {:ok, term(), [term()]} | {:error, Exception.t()}
  def execute(
        %__MODULE__{instruction: instruction, flow: flow_metadata} = node,
        input,
        run_context,
        meta \\ %{}
      ) do
    {durable?, run_context} = Map.pop(run_context, :__jido_exec_durable__, false)

    result =
      with :ok <- compatible_target(node) do
        case flow_metadata do
          %{mode: {:loop, %Loop{} = loop}} ->
            Loop.run_action(
              loop,
              instruction,
              input,
              Map.get(meta, :jido_loop, %{}),
              run_context,
              &execute_action/3
            )

          %{mode: {:invoke, phase}, component: component, params: params} ->
            execute_invoke(instruction, phase, component, params, input, run_context)

          %{mode: :handoff, component: component, params: params} ->
            execute_handoff(instruction, component, params, input, run_context)

          %{component: component, mode: {:map, on_error}, params: params} ->
            execute_map_component(instruction, component, params, on_error, input, run_context)

          %{
            component: component,
            mode: {:parallel, on_error, index, name},
            params: params
          } ->
            execute_parallel_component(
              instruction,
              component,
              params,
              on_error,
              index,
              name,
              input,
              run_context
            )

          %{component: component, params: params} ->
            execute_flow_component(instruction, component, params, input, run_context)

          nil ->
            params = merge_params(instruction.params, input)
            execute_action(instruction, params, run_context)
        end
      end

    result
    |> validate_durable_result(durable?)
    |> tag_flow_error(flow_metadata, input)
  end

  defp validate_durable_result({:ok, value, effects} = result, true) do
    with :ok <- Portable.validate(value, :output),
         :ok <- Portable.validate(effects, :effects) do
      result
    end
  end

  defp validate_durable_result(result, _durable?), do: result

  defp execute_map_component(
         instruction,
         component,
         _params,
         on_error,
         {:jido_map_item, index, item_id, resolved},
         run_context
       ) do
    result =
      with {:ok, params} <- resolved do
        execute_action(instruction, params, run_context)
      end

    case result do
      {:ok, output, effects} ->
        {:ok, {on_error, {:ok, output, effects}}, []}

      {:error, error} when on_error == :collect_errors ->
        error = collected_error(error, resolved, instruction.target, component, index, item_id)
        {:ok, {on_error, {:error, error}}, []}

      {:error, error} ->
        {:error, error}
    end
  end

  # A reference failure keeps its own details. An Action failure names its item.
  defp collected_error(
         %{type: _type, message: _message, details: _details, retryable?: _retryable?} = error,
         {:error, _reference_error},
         _action,
         _component,
         _index,
         _item_id
       ),
       do: drop_stacktrace(error)

  defp collected_error(error, {:error, _reference_error}, _action, _component, _index, _item_id),
    do: error |> Jido.Flow.Error.to_map() |> drop_stacktrace()

  defp collected_error(error, _resolved, action, component, index, item_id) do
    error
    |> Jido.Flow.Error.to_map()
    |> Map.update!(:details, fn details ->
      Map.merge(details, %{node: component, target: action, item_index: index, item_id: item_id})
    end)
    |> drop_stacktrace()
  end

  defp drop_stacktrace(error_map),
    do: Map.update!(error_map, :details, &Map.delete(&1, :stacktrace))

  defp execute_parallel_component(
         instruction,
         component,
         params,
         on_error,
         index,
         name,
         input,
         run_context
       ) do
    with {:ok, frame} <- Frame.merge(input) do
      result =
        with {:ok, resolved_params} <-
               ValueResolver.resolve(params, Frame.resolver_state(frame, run_context)) do
          execute_action(instruction, resolved_params, run_context)
        end

      case result do
        {:ok, output, effects} ->
          {:ok, {:jido_parallel_action, index, name, frame, {:ok, output, effects}}, []}

        {:error, error} when on_error == :collect_errors ->
          error = collected_parallel_error(error, instruction.target, component, index, name)
          {:ok, {:jido_parallel_action, index, name, frame, {:error, error}}, []}

        {:error, error} ->
          {:error, error}
      end
    end
  end

  defp collected_parallel_error(error, action, component, index, name) do
    error
    |> Jido.Flow.Error.to_map()
    |> Map.update!(:details, fn details ->
      Map.merge(details, %{
        node: component,
        target: action,
        action_index: index,
        action_name: name
      })
    end)
    |> drop_stacktrace()
  end

  defp execute_flow_component(instruction, component, params, input, run_context) do
    input = unwrap_flow_input(input)

    with {:ok, frame} <- Frame.merge(input),
         {:ok, resolved_params} <-
           ValueResolver.resolve(params, Frame.resolver_state(frame, run_context)),
         {:ok, output, effects} <- execute_action(instruction, resolved_params, run_context) do
      {:ok, Frame.put_result(frame, component, output, effects), []}
    end
  end

  defp execute_invoke(instruction, :decision, component, params, input, run_context) do
    with {:ok, frame} <- Frame.merge(input),
         {:ok, params} <-
           ValueResolver.resolve(
             params,
             Frame.resolver_state(frame, run_context)
           ),
         {:ok, output, effects} <- execute_action(instruction, params, run_context) do
      {:ok, {:jido_invoke_decision, frame, component, output, effects}, []}
    end
  end

  defp execute_invoke(
         instruction,
         :expander,
         _invoke,
         _params,
         {:jido_invoke_decision, frame, component, decision, effects},
         run_context
       ) do
    context = action_context(instruction, run_context)
    action = instruction.target

    with {:ok, params} <- Validation.callback(action, :validate_params, decision, :input) do
      case call_action(action, params, context, :invoke) do
        {:continue, input, target} ->
          {:ok, {:jido_invoke_continue, frame, component, input, target, effects}, []}

        {:ok, output, requests} ->
          invoke_output(instruction, frame, component, output, effects, requests, run_context)

        {:error, error} ->
          {:error, error}
      end
    end
  end

  defp execute_invoke(
         instruction,
         :target,
         component,
         params,
         frame,
         run_context
       ) do
    with {:ok, frame} <- Frame.merge(frame),
         effects = Frame.effects_for(frame, component),
         {:ok, output, requests} <- execute_action(instruction, params, run_context) do
      {:ok, {:jido_invoke_target_result, frame, component, output, effects ++ requests}, []}
    end
  end

  defp invoke_output(instruction, frame, component, output, effects, requests, _run_context) do
    action = instruction.target

    with {:ok, output} <- Validation.callback(action, :validate_output, output, :output) do
      {:ok, {:jido_invoke_finish, frame, component, output, effects ++ requests}, []}
    end
  end

  defp execute_handoff(instruction, component, params, input, run_context) do
    with {:ok, frame} <- Frame.merge(input),
         {:ok, params} <-
           ValueResolver.resolve(params, Frame.resolver_state(frame, run_context)),
         result <-
           call_action(
             instruction.target,
             params,
             action_context(instruction, run_context),
             :handoff
           ) do
      case result do
        {:handoff, successor_input, target} ->
          with {:ok, handoff} <- Jido.Exec.Handoff.new(target, successor_input) do
            {:ok, {:jido_handoff, frame, component, handoff, []}, []}
          end

        {:error, error} ->
          {:error, error}

        other ->
          {:error,
           Error.execution_error("Handoff selector must return a handoff control result", %{
             action: instruction.target,
             phase: :run,
             return: other,
             reason: :invalid_handoff_return
           })}
      end
    end
  end

  defp unwrap_flow_input({:jido_choice_branch, true, frame}), do: frame
  defp unwrap_flow_input({:jido_choice_selection, _option, frame}), do: frame
  defp unwrap_flow_input(input), do: input

  defp execute_action(instruction, params, run_context) do
    context = action_context(instruction, run_context)
    action = instruction.target

    with {:ok, validated_params} <- Validation.callback(action, :validate_params, params, :input),
         {:ok, output, effects} <- call_action(action, validated_params, context),
         {:ok, validated_output} <- Validation.callback(action, :validate_output, output, :output) do
      {:ok, validated_output, effects}
    end
  end

  defp action_context(instruction, run_context) do
    instruction.context
    |> Runtime.caller_context()
    |> Map.merge(run_context)
  end

  # Invoke and Handoff are the only components that accept control returns.
  defp call_action(action, params, context, control \\ :none) do
    case Validation.apply(
           action,
           :run,
           [params, Runtime.user_context(context)],
           :run
         ) do
      {:ok, {:ok, output}} ->
        {:ok, output, []}

      {:ok, {:ok, output, effects}} when is_list(effects) ->
        if List.improper?(effects) do
          invalid_effects(action, effects)
        else
          {:ok, output, effects}
        end

      {:ok, {:ok, _output, effects}} ->
        invalid_effects(action, effects)

      {:ok, {:error, reason}} ->
        {:error, normalize_action_error(action, reason)}

      {:ok, {:error, reason, _effects}} ->
        {:error, normalize_action_error(action, reason)}

      {:ok, {:handoff, input, target}} when control == :handoff ->
        {:handoff, input, target}

      {:ok, {:handoff, _input, _target}} ->
        {:error,
         Error.execution_error("only a Handoff selector can hand off", %{
           action: action,
           phase: :run,
           reason: :unsupported_handoff
         })}

      {:ok, {:continue, input, target}} when control == :invoke ->
        {:continue, input, target}

      {:ok, {:continue, _input, _target} = continuation} ->
        {:error,
         Error.execution_error("Action continuations are not supported by Runic execution", %{
           action: action,
           phase: :run,
           return: continuation,
           reason: :unsupported_continuation
         })}

      {:ok, other} ->
        {:error,
         Error.execution_error("Action returned an invalid value", %{
           action: action,
           phase: :run,
           return: other,
           reason: :invalid_return
         })}

      {:error, error} ->
        {:error, error}
    end
  end

  defp normalize_action_error(_action, error) when is_exception(error), do: error

  defp normalize_action_error(action, reason) do
    Error.execution_error(error_message(reason), %{action: action, phase: :run, reason: reason})
  end

  defp invalid_effects(action, effects) do
    {:error,
     Error.execution_error("Action returned an invalid effects list", %{
       action: action,
       phase: :run,
       effects: effects,
       reason: :invalid_effects
     })}
  end

  defp merge_params(params, input) when is_map(params) and is_map(input),
    do: Map.merge(params, input)

  defp merge_params(params, input) when is_map(params), do: Map.put(params, :input, input)
  defp merge_params(_params, input) when is_map(input), do: input
  defp merge_params(_params, input), do: %{input: input}

  defp ports(:input, action) do
    [in: [type: :any, doc: "Action input", schema: portable_schema(action, "input_schema")]]
  end

  defp ports(:output, action) do
    [out: [type: :any, doc: "Action output", schema: portable_schema(action, "output_schema")]]
  end

  # Port schemas are descriptive. A schema without a JSON form still executes.
  defp portable_schema(action, key) do
    if function_exported?(action, :authoring_contract, 0) do
      action |> apply(:authoring_contract, []) |> Map.get(key, %{})
    else
      %{}
    end
  rescue
    ArgumentError -> %{}
  end

  defp action_name(action) do
    if function_exported?(action, :name, 0), do: action.name(), else: Atom.to_string(action)
  end

  defp compatible_target(%__MODULE__{instruction: instruction, target_version: expected}) do
    actual = target_version(instruction.target)

    if actual == expected do
      :ok
    else
      {:error,
       Error.config_error("Action target code changed after the graph was built", %{
         target: instruction.target,
         expected: expected,
         actual: actual,
         reason: :incompatible_target
       })}
    end
  end

  defp target_version(action), do: action.module_info(:md5)

  defp identity_value(value) when is_atom(value), do: Atom.to_string(value)
  defp identity_value(value) when is_binary(value), do: value
  defp identity_value(value), do: inspect(value)

  defp error_message(message) when is_binary(message), do: message
  defp error_message(message) when is_atom(message), do: Atom.to_string(message)
  defp error_message(message), do: inspect(message)

  defp tag_flow_error({:error, %{details: details} = error}, metadata, input)
       when is_map(metadata) and is_map(details) do
    component = Map.get(metadata, :component)

    flow_details =
      %{node: component, node_path: Map.get(metadata, :node_path, [component])}
      |> Map.merge(flow_position(input, metadata))
      |> maybe_put(:source, Map.get(metadata, :location))

    {:error, %{error | details: Map.merge(details, flow_details)}}
  end

  defp tag_flow_error(result, _metadata, _input), do: result

  defp flow_position({:jido_map_item, index, item_id, _params}, _metadata),
    do: %{item_index: index, item_id: item_id}

  defp flow_position(_input, %{mode: {:parallel, _on_error, index, name}}),
    do: %{action_index: index, action_name: name}

  defp flow_position({:jido_reduce, _status, _component, index, _accumulator}, %{
         mode: {:loop, loop}
       }),
       do: %{item_index: index, item_id: Frame.item_id(loop.id, index)}

  defp flow_position({:jido_iterate, _status, _component, _state, completed, _body}, _metadata),
    do: %{iteration_index: completed, state_revision: completed}

  defp flow_position(_input, _metadata), do: %{}

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)
end

defimpl Runic.Identity.Projectable, for: Jido.Exec.Node.Action do
  def identity_document(node) do
    %{kind: :jido_action, version: 1, id: inspect(node.id)}
  end
end

defimpl Runic.Component, for: Jido.Exec.Node.Action do
  alias Jido.Exec.Node.Action
  alias Runic.Workflow

  def connectable?(_node, _other), do: true

  def connect(%Action{} = node, to, workflow) when is_list(to) do
    join = to |> Enum.map(& &1.hash) |> Runic.Workflow.Join.new()

    workflow = Enum.reduce(to, workflow, &Workflow.add_step(&2, &1, join))

    workflow
    |> Workflow.add_step(join, node)
    |> register(node)
  end

  def connect(%Action{} = node, to, workflow) do
    workflow
    |> Workflow.add_step(to, node)
    |> register(node)
  end

  def source(%Action{} = node) do
    instruction = :erlang.term_to_binary(node.instruction)
    id = :erlang.term_to_binary(node.id)
    flow = :erlang.term_to_binary(node.flow)
    target_version = :erlang.term_to_binary(node.target_version)

    quote do
      Jido.Exec.Node.Action.new(
        :erlang.binary_to_term(unquote(instruction)),
        id: :erlang.binary_to_term(unquote(id)),
        name: unquote(node.name),
        flow: :erlang.binary_to_term(unquote(flow)),
        target_version: :erlang.binary_to_term(unquote(target_version))
      )
    end
  end

  def hash(%Action{hash: hash}), do: hash
  def inputs(%Action{inputs: inputs}), do: inputs
  def outputs(%Action{outputs: outputs}), do: outputs

  defp register(workflow, %Action{flow: nil} = node) do
    workflow
    |> Map.put(:output_ports, result: [type: :any, from: node.name])
    |> register_action(node)
  end

  defp register(workflow, node), do: register_action(workflow, node)

  defp register_action(workflow, node) do
    workflow
    |> Workflow.draw_connection(node, node, :component_of, properties: %{kind: :action})
    |> Workflow.register_component(node)
  end
end

defimpl Runic.Transmutable, for: Jido.Exec.Node.Action do
  alias Runic.Workflow

  def transmute(node), do: to_workflow(node)

  def to_workflow(node) do
    Workflow.new(
      name: to_string(node.name),
      output_ports: [result: [type: :any, from: node.name]]
    )
    |> Workflow.add(node)
  end

  def to_component(node), do: node
end

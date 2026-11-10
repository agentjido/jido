defmodule Jido.Exec.Node.Invoke do
  @moduledoc false

  require Runic

  alias Jido.Exec.{Frame, Runtime}
  alias Jido.Exec.Node.Action
  alias Jido.Exec.Node.Invoke.Completion
  alias Jido.Exec.Node.Invoke.Finish
  alias Jido.Instruction
  alias Runic.Identity
  alias Runic.Workflow
  alias Runic.Workflow.{Call, ChildInvocation}

  @enforce_keys [:id, :name, :hash, :component, :decision, :expander, :nested_compiler]
  defstruct [
    :id,
    :name,
    :hash,
    :component,
    :decision,
    :expander,
    :nested_compiler,
    :location,
    :node_path
  ]

  @type t :: %__MODULE__{}

  @doc false
  @spec new(keyword()) :: t()
  def new(opts) do
    opts =
      Keyword.validate!(opts, [
        :id,
        :name,
        :component,
        :decision,
        :expander,
        :nested_compiler,
        :location,
        :node_path
      ])

    id = Keyword.fetch!(opts, :id)

    %__MODULE__{
      id: id,
      name: Keyword.fetch!(opts, :name),
      hash:
        Identity.digest(:component_definition, %{
          kind: "jido_invoke",
          version: 1,
          id: inspect(id)
        }),
      component: Keyword.fetch!(opts, :component),
      decision: Keyword.fetch!(opts, :decision),
      expander: Keyword.fetch!(opts, :expander),
      nested_compiler:
        opts
        |> Keyword.fetch!(:nested_compiler)
        |> Jido.Exec.NestedCompiler.validate!(),
      location: Keyword.get(opts, :location),
      node_path: Keyword.get(opts, :node_path, [Keyword.fetch!(opts, :component)])
    }
  end

  @doc false
  @spec connect(t(), [term()], Workflow.t()) :: Workflow.t()
  def connect(%__MODULE__{} = node, parents, %Workflow{} = workflow) do
    decision = action(node, :decision, node.decision, node.decision.params)
    expander = action(node, :expander, node.expander, nil)
    condition = Finish.condition(node.id, node.name, node.component)
    completion = Completion.new(node)

    workflow
    |> connect_from(parents, decision)
    |> Workflow.add_step(decision, expander)
    |> Workflow.add_step(expander, node)
    |> Workflow.add_step(node, condition)
    |> Workflow.add_step(condition, completion)
    |> Workflow.register_component(condition)
    |> Workflow.register_component(completion)
    |> Workflow.draw_connection(node, node, :component_of, properties: %{kind: :invoke})
    |> Workflow.register_component(node)
  end

  @doc false
  @spec expansion(t(), term(), term(), term(), map()) ::
          {term(), (Workflow.t() -> Workflow.t())} | no_return()
  def expansion(node, target, input, frame, runtime) do
    with {:ok, target_instruction} <- Instruction.resolve(target),
         {:ok, instruction} <- Instruction.resolve(target_instruction, input) do
      case instruction do
        %Instruction{kind: :action} ->
          target_id = target_id(node, target_instruction)
          action_target(node, instruction, frame, target_id)

        %Instruction{kind: :flow} ->
          target_id = target_id(node, instruction)
          {{:jido_invoke_flow_target, target_id, frame}, flow_target(node, instruction, runtime, target_id)}
      end
    else
      {:error, %{details: details} = error} when is_map(details) ->
        raise %{
          error
          | details:
              Map.merge(details, %{
                node: node.component,
                node_path: node.node_path,
                phase: :invoke
              })
        }
    end
  end

  @doc false
  @spec finish(term()) :: {:ok, term()} | {:continue, term()}
  def finish({:jido_invoke_finish, frame, component, output, effects}) do
    {:ok, Frame.put_result(frame, component, output, effects)}
  end

  def finish({:jido_invoke_continue, _frame, _component, _input, _target, _effects} = value),
    do: {:continue, value}

  @doc false
  @spec target?(term(), term()) :: boolean()
  def target?({:jido_invoke_flow_target, target_id, _frame}, target_id), do: true
  def target?(_value, _target_id), do: false

  @doc false
  @spec target_condition(term(), term(), term()) :: Runic.Workflow.Condition.t()
  def target_condition(id, name, target_id) do
    source =
      quote do
        Jido.Exec.Node.Invoke.target_condition(
          unquote(Macro.escape(id)),
          unquote(name),
          unquote(target_id)
        )
      end

    %Runic.Workflow.Condition{
      name: internal_name(%{name: name}, "route/#{target_id}"),
      hash:
        Identity.digest(:component_definition, %{
          kind: "jido_invoke_target_route",
          version: 1,
          id: inspect({id, target_id})
        }),
      work: fn value -> target?(value, target_id) end,
      arity: 1,
      closure: Runic.Closure.new(source, %{}, nil),
      meta_refs: []
    }
  end

  defp action(node, phase, instruction, params, target_id \\ nil) do
    flow = %{
      component: node.component,
      mode: {:invoke, phase},
      params: params,
      location: node.location,
      node_path: node.node_path
    }

    id = if target_id, do: {node.id, phase, target_id}, else: {node.id, phase}
    suffix = if target_id, do: "#{phase}/#{target_id}", else: Atom.to_string(phase)

    Action.new(instruction, flow: flow, id: id, name: internal_name(node, suffix))
  end

  defp action_target(node, instruction, frame, target_id) do
    target = action(node, :target, instruction, instruction.params, target_id)
    request = ChildInvocation.new(target: target, input: frame)

    call =
      Call.new(Runic.step(fn request -> request end),
        name: internal_name(node, "call/#{target_id}")
      )

    finish = Finish.new(node, target_id)

    apply_fn = fn workflow ->
      workflow
      |> Workflow.add(call, to: node)
      |> Workflow.add(finish, connections: [[from: {call.name, :out}, to: :in]])
    end

    {request, apply_fn}
  end

  defp flow_target(node, instruction, runtime, target_id) do
    target_key = Finish.target_component_key(node, target_id)
    base_name = internal_name(node, "target/#{target_id}")
    route = target_condition(node.id, node.name, target_id)

    compiled_target =
      node.nested_compiler.compile_nested!(instruction,
        namespace: base_name,
        boundary_name: base_name,
        parent_component: target_key,
        input_params: instruction.params,
        boundary_location: node.location,
        node_path_prefix: node.node_path
      )

    target =
      Workflow.new(
        name: "#{base_name}/invocation",
        input_ports: [in: [type: :any]],
        output_ports: [result: [type: :any, from: compiled_target.name]]
      )
      |> Workflow.add(route)
      |> Workflow.add(compiled_target, to: route)

    case Jido.Exec.Node.Wait.validate_host(target, runtime) do
      :ok -> :ok
      {:error, error} -> raise error
    end

    finish = Finish.new(node, target_id)

    fn workflow ->
      context =
        instruction.context
        |> Runtime.caller_context()
        |> Map.merge(runtime)

      workflow
      |> Workflow.add(target, to: node)
      |> put_target_context(target, context)
      |> Workflow.add(finish, connections: [[from: {target.name, :result}, to: :in]])
    end
  end

  defp target_id(node, %Instruction{} = instruction) do
    Identity.digest(:component_definition, %{
      kind: "jido_invoke_target",
      version: 1,
      invoke: inspect(node.id),
      target: target_identity(instruction.target),
      call_data: call_data_identity(instruction)
    })
    |> to_string()
  end

  defp call_data_identity(%Instruction{} = instruction) do
    {instruction.params, instruction.context}
    |> :erlang.term_to_binary([:deterministic])
    |> then(&:crypto.hash(:sha256, &1))
  end

  defp target_identity(%Jido.Flow{} = flow),
    do: %{flow: Jido.Flow.Identity.semantic_digest(flow)}

  defp target_identity(target) when is_atom(target) do
    version =
      if function_exported?(target, :module_info, 1), do: target.module_info(:md5), else: nil

    %{module: target, version: version}
  end

  defp put_target_context(workflow, _target, context) when map_size(context) == 0,
    do: workflow

  defp put_target_context(workflow, target, context) do
    scoped =
      target.graph
      |> Multigraph.vertices()
      |> Enum.reduce(%{}, fn
        %{name: name}, acc when is_atom(name) or is_binary(name) -> Map.put(acc, name, context)
        _node, acc -> acc
      end)

    Workflow.put_run_context(workflow, scoped)
  end

  defp connect_from(workflow, [], child), do: Workflow.add_step(workflow, child)
  defp connect_from(workflow, [parent], child), do: Workflow.add_step(workflow, parent, child)
  defp connect_from(workflow, parents, child), do: Workflow.add_step(workflow, parents, child)

  defp internal_name(node, suffix), do: "__jido_invoke__/#{node.name}/#{suffix}"
end

defimpl Runic.Identity.Projectable, for: Jido.Exec.Node.Invoke do
  def identity_document(node), do: %{kind: :jido_invoke, version: 1, id: inspect(node.id)}
end

defimpl Runic.Workflow.Invokable, for: Jido.Exec.Node.Invoke do
  alias Jido.Exec.Frame
  alias Jido.Exec.Node.Invoke
  alias Runic.Workflow
  alias Runic.Workflow.{CausalContext, Runnable}
  alias Runic.Workflow.Events.{ActivationConsumed, FactProduced}

  def match_or_execute(_node), do: :execute

  def invoke(node, workflow, fact) do
    {:ok, runnable} = prepare(node, workflow, fact)
    Workflow.apply_runnable(workflow, execute(node, runnable))
  end

  def prepare(node, workflow, fact) do
    context =
      CausalContext.new(
        node_hash: node.hash,
        input_fact: fact,
        run_context: Workflow.get_run_context(workflow, node.name),
        ancestry_depth: Workflow.ancestry_depth(workflow, fact)
      )

    {:ok, Runnable.new(node, fact, context)}
  end

  def execute(node, %Runnable{input_fact: fact, context: context} = runnable) do
    case Invoke.finish(Jido.Exec.Fact.value(fact)) do
      {:ok, value} ->
        complete(runnable, node, fact, value, context, [])

      {:continue, {:jido_invoke_continue, frame, component, input, target, effects}} ->
        frame = Frame.put_result(frame, component, nil, effects)
        {value, apply_fn} = Invoke.expansion(node, target, input, frame, context.run_context)
        complete(runnable, node, fact, value, context, [apply_fn])
    end
  rescue
    error -> Runnable.fail(runnable, error)
  catch
    kind, reason -> Runnable.fail(runnable, {kind, reason})
  end

  defp complete(runnable, node, fact, value, context, apply_fns) do
    result = Jido.Exec.Fact.child(fact, value: value, ancestry: {node.hash, fact.hash})

    Runnable.complete(
      runnable,
      result,
      [
        FactProduced.new(result, producer_label: :produced, weight: context.ancestry_depth + 1),
        %ActivationConsumed{fact_hash: fact.hash, node_hash: node.hash, from_label: :runnable}
      ],
      apply_fns
    )
  end
end

defimpl Runic.Component, for: Jido.Exec.Node.Invoke do
  alias Jido.Exec.Node.Invoke

  def connectable?(_node, _other), do: true
  def connect(node, to, workflow), do: Invoke.connect(node, List.wrap(to), workflow)

  def source(node) do
    quote do
      Jido.Exec.Node.Invoke.new(
        id: unquote(Macro.escape(node.id)),
        name: unquote(node.name),
        component: unquote(node.component),
        decision: unquote(Macro.escape(node.decision)),
        expander: unquote(Macro.escape(node.expander)),
        nested_compiler: unquote(node.nested_compiler),
        location: unquote(Macro.escape(node.location)),
        node_path: unquote(Macro.escape(node.node_path))
      )
    end
  end

  def hash(node), do: node.hash
  def inputs(_node), do: [in: [type: :any]]
  def outputs(_node), do: [out: [type: :any]]
end

defmodule Jido.Exec.Node.Loop do
  @moduledoc false

  alias Jido.Action.Validation
  alias Jido.Exec.{Frame, ValueResolver}
  alias Jido.Exec.Node.Action
  alias Jido.Exec.Node.Loop.Start
  alias Jido.Flow.Error
  alias Jido.Instruction
  alias Runic.Identity
  alias Runic.Workflow

  @enforce_keys [:id, :name, :hash, :kind, :component, :call]
  defstruct [
    :id,
    :name,
    :hash,
    :kind,
    :component,
    :call,
    :collection,
    :initial,
    :state,
    :completion,
    :max_iterations,
    :location,
    :node_path
  ]

  @type kind :: :reduce | :iterate
  @type t :: %__MODULE__{}

  @doc false
  @spec new(keyword()) :: t()
  def new(opts) do
    opts =
      Keyword.validate!(opts, [
        :id,
        :name,
        :kind,
        :component,
        :call,
        :collection,
        :initial,
        :state,
        :completion,
        :max_iterations,
        :location,
        :node_path
      ])

    id = Keyword.fetch!(opts, :id)
    kind = Keyword.fetch!(opts, :kind)

    unless kind in [:reduce, :iterate] do
      raise ArgumentError, "loop kind must be :reduce or :iterate"
    end

    %__MODULE__{
      id: id,
      name: Keyword.fetch!(opts, :name),
      hash:
        Identity.digest(:component_definition, %{
          kind: "jido_#{kind}",
          version: 1,
          id: inspect(id)
        }),
      kind: kind,
      component: Keyword.fetch!(opts, :component),
      call: Keyword.fetch!(opts, :call),
      collection: Keyword.get(opts, :collection),
      initial: Keyword.get(opts, :initial),
      state: Keyword.get(opts, :state),
      completion: Keyword.get(opts, :completion),
      max_iterations: Keyword.get(opts, :max_iterations),
      location: Keyword.get(opts, :location),
      node_path: Keyword.get(opts, :node_path, [Keyword.fetch!(opts, :component)])
    }
  end

  @doc false
  @spec connect(t(), [term()], Workflow.t()) :: Workflow.t()
  def connect(%__MODULE__{} = node, parents, %Workflow{} = workflow) do
    start = Start.new(node)

    continue =
      condition(
        {node.id, :continue},
        internal_name(node, "continue"),
        :continue
      )

    complete =
      condition(
        {node.id, :complete},
        internal_name(node, "complete"),
        :complete
      )

    flow = %{
      component: node.component,
      mode: {:loop, node},
      location: node.location,
      node_path: node.node_path
    }

    action =
      Action.new(node.call,
        flow: flow,
        id: {node.id, :action},
        name: internal_name(node, "action")
      )

    workflow
    |> connect_from(parents, start)
    |> Workflow.add_step(start, continue)
    |> Workflow.add_step(start, complete)
    |> Workflow.add_step(continue, action)
    |> Workflow.add_step(action, continue)
    |> Workflow.add_step(action, complete)
    |> Workflow.add_step(complete, node)
    |> Workflow.draw_connection(node, node, :component_of, properties: %{kind: node.kind})
    |> Workflow.register_component(node)
  end

  @doc false
  @spec start(t(), term(), term()) :: {:ok, term(), map()} | {:error, term()}
  def start(%__MODULE__{kind: :reduce} = node, input, context) do
    with {:ok, frame} <- Frame.merge(input),
         state = Frame.resolver_state(frame, context),
         {:ok, collection} <- ValueResolver.resolve(node.collection, state),
         {:ok, items} <- enumerable(collection, node),
         {:ok, initial} <- ValueResolver.resolve(node.initial, state),
         :ok <- validate_reduce_initial(node, initial) do
      status = if items == [], do: :complete, else: :continue
      {:ok, {:jido_reduce, status, node.component, 0, initial}, %{frame: frame, items: items}}
    end
  end

  def start(%__MODULE__{kind: :iterate} = node, input, context) do
    with {:ok, frame} <- Frame.merge(input),
         resolver = Frame.resolver_state(frame, context),
         {:ok, initial} <- ValueResolver.resolve(node.state.initial, resolver),
         {:ok, initial} <- validate_iterate_state(node, initial, :initial, 0),
         {:ok, complete?} <- iterate_complete?(node, frame, initial, 0, nil, context) do
      status = if complete?, do: :complete, else: :continue
      {:ok, {:jido_iterate, status, node.component, initial, 0, nil}, %{frame: frame}}
    end
  end

  @doc false
  # Iteration values hold only loop progress. The frame and items ride in the
  # loop Fact meta, which is not part of Fact identity, so per-iteration cost
  # does not grow with the frame. Effects accumulate through the Fact meta.
  @spec run_action(t(), Instruction.t(), term(), map(), term(), function()) ::
          {:ok, term(), [term()]} | {:error, term()}
  def run_action(
        %__MODULE__{kind: :reduce} = node,
        instruction,
        {:jido_reduce, :continue, component, index, accumulator},
        %{frame: frame, items: items},
        context,
        action_runner
      ) do
    resolver =
      frame
      |> Frame.resolver_state(context)
      |> Map.merge(%{
        item: Enum.at(items, index),
        item_index: index,
        item_id: Frame.item_id(node.id, index),
        accumulator: accumulator
      })

    with {:ok, params} <- ValueResolver.resolve(node.call.params, resolver),
         {:ok, output, requests} <- action_runner.(instruction, params, context) do
      next_index = index + 1
      status = if next_index == length(items), do: :complete, else: :continue
      {:ok, {:jido_reduce, status, component, next_index, output}, requests}
    end
  end

  def run_action(
        %__MODULE__{kind: :iterate} = node,
        instruction,
        {:jido_iterate, :continue, component, state, completed, body_result},
        %{frame: frame},
        context,
        action_runner
      ) do
    resolver =
      frame
      |> Frame.resolver_state(context)
      |> Map.merge(%{
        iterate_state: state,
        iteration_index: completed,
        body_result: body_result
      })

    with {:ok, params} <- ValueResolver.resolve(node.call.params, resolver),
         {:ok, output, requests} <- action_runner.(instruction, params, context),
         {:ok, candidate} <-
           ValueResolver.resolve(node.state.update, Map.put(resolver, :body_result, output)),
         next_completed = completed + 1,
         {:ok, next_state} <-
           validate_iterate_state(node, candidate, :update, next_completed),
         {:ok, complete?} <-
           iterate_complete?(node, frame, next_state, next_completed, output, context),
         :ok <- within_iteration_limit(node, complete?, next_completed, next_state) do
      status = if complete?, do: :complete, else: :continue
      {:ok, {:jido_iterate, status, component, next_state, next_completed, output}, requests}
    end
  end

  @doc false
  @spec continue?(term()) :: boolean()
  def continue?({:jido_reduce, :continue, _, _, _}), do: true
  def continue?({:jido_iterate, :continue, _, _, _, _}), do: true
  def continue?(_value), do: false

  @doc false
  @spec complete?(term()) :: boolean()
  def complete?({:jido_reduce, :complete, _, _, _}), do: true
  def complete?({:jido_iterate, :complete, _, _, _, _}), do: true
  def complete?(_value), do: false

  @doc false
  @spec finish(t(), term(), map()) :: {:ok, term()}
  def finish(
        %__MODULE__{kind: :reduce},
        {:jido_reduce, :complete, component, _index, accumulator},
        %{jido_loop: %{frame: frame}} = meta
      ) do
    {:ok, Frame.put_result(frame, component, accumulator, loop_effects(meta))}
  end

  def finish(
        %__MODULE__{kind: :iterate},
        {:jido_iterate, :complete, component, state, completed, body_result},
        %{jido_loop: %{frame: frame}} = meta
      ) do
    output = %{
      kind: :jido_flow_iterate_result,
      iterations: completed,
      state: state,
      output: body_result
    }

    {:ok, Frame.put_result(frame, component, output, loop_effects(meta))}
  end

  defp loop_effects(meta), do: get_in(meta, [:jido, :effects]) || []

  @doc false
  @spec condition(term(), term(), :continue | :complete) :: struct()
  def condition(id, name, status) when status in [:continue, :complete] do
    hash =
      Identity.digest(:component_definition, %{
        kind: "jido_loop_condition",
        version: 1,
        id: inspect(id),
        status: status
      })

    source =
      quote do
        Jido.Exec.Node.Loop.condition(
          unquote(Macro.escape(id)),
          unquote(name),
          unquote(status)
        )
      end

    work = if status == :continue, do: &__MODULE__.continue?/1, else: &__MODULE__.complete?/1

    %Runic.Workflow.Condition{
      name: name,
      hash: hash,
      work: work,
      arity: 1,
      closure: Runic.Closure.new(source, %{}, nil),
      meta_refs: []
    }
  end

  defp iterable_error(node, value) do
    Error.execution_error("Reduce collection is not enumerable", %{
      node: node.component,
      phase: :reduce_collection,
      value: value,
      retry: false
    })
  end

  defp validate_reduce_initial(_node, value)
       when is_map(value) and not is_struct(value),
       do: :ok

  defp validate_reduce_initial(_node, %Jido.Action.Output{}), do: :ok

  defp validate_reduce_initial(node, value) do
    {:error,
     Error.execution_error("reduce initial value must be a map or Jido.Action.Output", %{
       node: node.component,
       phase: :reduce_initial,
       value: value,
       retry: false
     })}
  end

  defp enumerable(value, node) do
    if is_nil(Enumerable.impl_for(value)) do
      {:error, iterable_error(node, value)}
    else
      {:ok, Enum.to_list(value)}
    end
  end

  defp validate_iterate_state(node, value, phase, revision) do
    details = %{
      node: node.component,
      phase: if(phase == :initial, do: :iterate_state_initial, else: :iterate_state_update),
      state_revision: revision,
      retry: false
    }

    if is_map(value) and not is_struct(value) do
      case Validation.parse_preserving_shape(node.state.schema, value, details) do
        {:ok, validated} when is_map(validated) and not is_struct(validated) ->
          {:ok, validated}

        {:ok, validated} ->
          {:error,
           Error.execution_error(
             "iterator state schema must return a plain map",
             Map.merge(details, %{reason: :not_a_plain_map, value: validated})
           )}

        {:error, _reason} ->
          {:error, Error.invalid_execution_error("iterator state schema validation failed", details)}
      end
    else
      message =
        if phase == :initial,
          do: "iterator initial state must resolve to a plain map",
          else: "iterator state update must resolve to a plain map"

      {:error,
       Error.execution_error(
         message,
         Map.merge(details, %{reason: :not_a_plain_map, value: value})
       )}
    end
  end

  defp iterate_complete?(node, frame, state, completed, body_result, context) do
    resolver =
      frame
      |> Frame.resolver_state(context)
      |> Map.merge(%{
        iterate_state: state,
        iteration_index: completed,
        body_result: body_result
      })

    case ValueResolver.resolve(node.completion, resolver) do
      {:ok, value} when is_boolean(value) ->
        {:ok, value}

      {:ok, value} ->
        {:error,
         Error.execution_error("invalid iterator completion condition operands", %{
           phase: :iterate_completion,
           node: node.component,
           iterations: completed,
           reason: :invalid_boolean_operand,
           value: value,
           expression_path: [],
           retry: false
         })}

      {:error, error} ->
        {:error, put_loop_details(error, node, :iterate_completion, completed)}
    end
  end

  defp within_iteration_limit(_node, true, _completed, _state), do: :ok

  defp within_iteration_limit(node, false, completed, state)
       when completed >= node.max_iterations do
    {:error,
     Error.execution_error("flow iterator exhausted maximum iterations", %{
       phase: :iterate_exhaustion,
       node: node.component,
       max_iterations: node.max_iterations,
       completed_iterations: completed,
       state_revision: completed,
       state: state,
       retry: false
     })}
  end

  defp within_iteration_limit(_node, false, _completed, _state), do: :ok

  defp put_loop_details(%{details: details} = error, node, phase, completed)
       when is_map(details) do
    %{
      error
      | details:
          Map.merge(details, %{
            phase: phase,
            node: node.component,
            iterations: completed,
            retry: false
          })
    }
  end

  defp put_loop_details(error, _node, _phase, _completed), do: error

  defp connect_from(workflow, [], child), do: Workflow.add_step(workflow, child)
  defp connect_from(workflow, [parent], child), do: Workflow.add_step(workflow, parent, child)
  defp connect_from(workflow, parents, child), do: Workflow.add_step(workflow, parents, child)

  defp internal_name(node, kind), do: "__jido_#{node.kind}__/#{node.name}/#{kind}"
end

defimpl Runic.Identity.Projectable, for: Jido.Exec.Node.Loop do
  def identity_document(node) do
    %{kind: node.kind, version: 1, id: inspect(node.id)}
  end
end

defimpl Runic.Workflow.Invokable, for: Jido.Exec.Node.Loop do
  alias Jido.Exec.Node.Loop
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
        ancestry_depth: Workflow.ancestry_depth(workflow, fact)
      )

    {:ok, Runnable.new(node, fact, context)}
  end

  def execute(node, %Runnable{input_fact: fact, context: context} = runnable) do
    case Loop.finish(node, Jido.Exec.Fact.value(fact), fact.meta) do
      {:ok, value} ->
        result = Jido.Exec.Fact.child(fact, value: value, ancestry: {node.hash, fact.hash})

        Runnable.complete(runnable, result, [
          FactProduced.new(result, producer_label: :produced, weight: context.ancestry_depth + 1),
          %ActivationConsumed{fact_hash: fact.hash, node_hash: node.hash, from_label: :runnable}
        ])
    end
  end
end

defimpl Runic.Component, for: Jido.Exec.Node.Loop do
  alias Jido.Exec.Node.Loop

  def connectable?(_node, _other), do: true
  def connect(node, to, workflow), do: Loop.connect(node, List.wrap(to), workflow)

  def source(node) do
    quote do
      Jido.Exec.Node.Loop.new(
        id: unquote(Macro.escape(node.id)),
        name: unquote(node.name),
        kind: unquote(node.kind),
        component: unquote(node.component),
        call: unquote(Macro.escape(node.call)),
        collection: unquote(Macro.escape(node.collection)),
        initial: unquote(Macro.escape(node.initial)),
        state: unquote(Macro.escape(node.state)),
        completion: unquote(Macro.escape(node.completion)),
        max_iterations: unquote(node.max_iterations),
        location: unquote(Macro.escape(node.location)),
        node_path: unquote(Macro.escape(node.node_path))
      )
    end
  end

  def hash(node), do: node.hash
  def inputs(_node), do: [in: [type: :any]]
  def outputs(_node), do: [out: [type: :any]]
end

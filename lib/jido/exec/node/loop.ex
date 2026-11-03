defmodule Jido.Exec.Node.Loop do
  @moduledoc false

  alias Jido.Exec.Frame
  alias Jido.Exec.Node.Action
  alias Jido.Exec.Node.Loop.Start
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

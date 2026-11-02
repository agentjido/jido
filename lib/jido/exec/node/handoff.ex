defmodule Jido.Exec.Node.Handoff do
  @moduledoc false

  alias Jido.Exec.Node.Action
  alias Runic.Identity
  alias Runic.Workflow

  @enforce_keys [:id, :name, :hash, :component, :selector]
  defstruct [:id, :name, :hash, :component, :selector, :location, :node_path]

  @type t :: %__MODULE__{}

  @doc false
  @spec new(keyword()) :: t()
  def new(opts) do
    opts =
      Keyword.validate!(opts, [
        :id,
        :name,
        :component,
        :selector,
        :location,
        :node_path
      ])

    id = Keyword.fetch!(opts, :id)

    %__MODULE__{
      id: id,
      name: Keyword.fetch!(opts, :name),
      hash:
        Identity.digest(:component_definition, %{
          kind: "jido_handoff",
          version: 1,
          id: inspect(id)
        }),
      component: Keyword.fetch!(opts, :component),
      selector: Keyword.fetch!(opts, :selector),
      location: Keyword.get(opts, :location),
      node_path: Keyword.get(opts, :node_path, [Keyword.fetch!(opts, :component)])
    }
  end

  @doc false
  @spec connect(t(), [term()], Workflow.t()) :: Workflow.t()
  def connect(%__MODULE__{} = node, parents, %Workflow{} = workflow) do
    flow = %{
      component: node.component,
      mode: :handoff,
      params: node.selector.params,
      location: node.location,
      node_path: node.node_path
    }

    selector =
      Action.new(node.selector,
        flow: flow,
        id: {node.id, :selector},
        name: "__jido_handoff__/#{node.name}/selector"
      )

    workflow
    |> connect_from(parents, selector)
    |> Workflow.add_step(selector, node)
    |> Workflow.draw_connection(node, node, :component_of, properties: %{kind: :handoff})
    |> Workflow.register_component(node)
  end

  defp connect_from(workflow, [], child), do: Workflow.add_step(workflow, child)
  defp connect_from(workflow, [parent], child), do: Workflow.add_step(workflow, parent, child)
  defp connect_from(workflow, parents, child), do: Workflow.add_step(workflow, parents, child)
end

defimpl Runic.Identity.Projectable, for: Jido.Exec.Node.Handoff do
  def identity_document(node), do: %{kind: :jido_handoff, version: 1, id: inspect(node.id)}
end

defimpl Runic.Workflow.Invokable, for: Jido.Exec.Node.Handoff do
  alias Jido.Exec.Frame
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
    case Jido.Exec.Fact.value(fact) do
      {:jido_handoff, frame, component, request, effects} ->
        value = Frame.put_result(frame, component, request, effects)

        result =
          Jido.Exec.Fact.child(fact,
            value: value,
            meta: %{jido: %{control: :handoff}},
            ancestry: {node.hash, fact.hash}
          )

        Runnable.complete(
          runnable,
          result,
          [
            FactProduced.new(result,
              producer_label: :produced,
              weight: context.ancestry_depth + 1
            ),
            %ActivationConsumed{fact_hash: fact.hash, node_hash: node.hash, from_label: :runnable}
          ],
          []
        )

      value ->
        Runnable.fail(runnable, {:invalid_handoff_control, value})
    end
  rescue
    error -> Runnable.fail(runnable, error)
  catch
    kind, reason -> Runnable.fail(runnable, {kind, reason})
  end
end

defimpl Runic.Component, for: Jido.Exec.Node.Handoff do
  alias Jido.Exec.Node.Handoff

  def connectable?(_node, _other), do: true
  def connect(node, to, workflow), do: Handoff.connect(node, List.wrap(to), workflow)

  def source(node) do
    quote do
      Jido.Exec.Node.Handoff.new(
        id: unquote(Macro.escape(node.id)),
        name: unquote(node.name),
        component: unquote(node.component),
        selector: unquote(Macro.escape(node.selector)),
        location: unquote(Macro.escape(node.location)),
        node_path: unquote(Macro.escape(node.node_path))
      )
    end
  end

  def hash(node), do: node.hash
  def inputs(_node), do: [in: [type: :any]]
  def outputs(_node), do: [out: [type: :any]]
end

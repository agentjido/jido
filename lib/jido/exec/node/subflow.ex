defmodule Jido.Exec.Node.Subflow do
  @moduledoc false

  use Runic.Workflow.SingleOutput, batch_parent: false

  alias Jido.Exec.ValueResolver
  alias Jido.Exec.Node.{FlowTarget, Lifecycle, Targets}
  alias Jido.Instruction
  alias Runic.Identity
  alias Runic.Workflow.SingleOutput.Context
  alias Runic.Workflow.SingleOutput.Result, as: SingleOutputResult

  @derive {Inspect, only: [:id, :name, :node_path]}
  @enforce_keys [:id, :name, :hash, :definition, :target_versions, :child_workflow, :node_path]
  defstruct [:id, :name, :hash, :definition, :target_versions, :child_workflow, :node_path, :location]

  @type t :: %__MODULE__{}

  @doc false
  @spec new(keyword()) :: t()
  def new(opts) do
    opts =
      Keyword.validate!(opts, [
        :id,
        :name,
        :definition,
        :target_versions,
        :child_workflow,
        :location,
        :node_path
      ])

    id = Keyword.fetch!(opts, :id)
    name = Keyword.fetch!(opts, :name)
    definition = Keyword.fetch!(opts, :definition)

    %__MODULE__{
      id: id,
      name: name,
      hash:
        Identity.digest(:component_definition, %{
          kind: :jido_flow_subflow,
          version: 1,
          id: inspect(id)
        }),
      definition: definition,
      target_versions: Keyword.get_lazy(opts, :target_versions, fn -> Targets.versions(definition) end),
      child_workflow: Keyword.fetch!(opts, :child_workflow),
      location: Keyword.get(opts, :location),
      node_path: Keyword.get(opts, :node_path, [name])
    }
  end

  @impl Runic.Workflow.SingleOutput
  @doc false
  @spec run(t(), term(), Context.t()) :: SingleOutputResult.t()
  def run(%__MODULE__{} = node, input, %Context{} = context) do
    Lifecycle.run(node, input, context, fn bindings ->
      state = ValueResolver.resolver_state(bindings, context.runtime)
      call = node.definition.call

      with :ok <- Targets.compatible(node.target_versions),
           {:ok, params} <- ValueResolver.resolve(call.params, state),
           {:ok, instruction} <- Instruction.resolve(call.target, params) do
        FlowTarget.run(instruction, context.runtime, node, node.child_workflow)
      end
    end)
  end
end

defimpl Runic.Identity.Projectable, for: Jido.Exec.Node.Subflow do
  def identity_document(node),
    do: %{kind: :jido_flow_subflow, version: 1, id: inspect(node.id)}
end

defimpl Runic.Component, for: Jido.Exec.Node.Subflow do
  alias Jido.Exec.Node.Subflow
  alias Runic.Workflow

  def connectable?(_node, _other), do: true

  def connect(%Subflow{} = node, parents, workflow) when is_list(parents) do
    join = parents |> Enum.map(& &1.hash) |> Workflow.Join.new()
    workflow = Enum.reduce(parents, workflow, &Workflow.add_step(&2, &1, join))
    connect(node, join, workflow)
  end

  def connect(%Subflow{} = node, parent, workflow) do
    workflow
    |> Workflow.add_step(parent, node)
    |> Workflow.draw_connection(node, node, :component_of, properties: %{kind: :call})
    |> Workflow.register_component(node)
  end

  def source(%Subflow{} = node) do
    quote do
      Jido.Exec.Node.Subflow.new(
        id: unquote(Macro.escape(node.id)),
        name: unquote(node.name),
        definition: unquote(Macro.escape(node.definition)),
        target_versions: unquote(Macro.escape(node.target_versions)),
        child_workflow: unquote(Macro.escape(node.child_workflow)),
        location: unquote(Macro.escape(node.location)),
        node_path: unquote(Macro.escape(node.node_path))
      )
    end
  end

  def hash(%Subflow{hash: hash}), do: hash
  def inputs(_node), do: [bindings: [type: :any, doc: "Subflow bindings"]]

  def outputs(_node) do
    [
      value: [type: :any, doc: "Subflow value"],
      effects: [type: :any, doc: "Subflow effects"],
      control: [type: :any, doc: "Subflow control result"]
    ]
  end
end

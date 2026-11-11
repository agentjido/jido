defmodule Jido.Exec.Node.Invoke do
  @moduledoc false

  use Runic.Workflow.SingleOutput, batch_parent: false

  alias Jido.Error
  alias Jido.Exec.{ActionBoundary, Runtime, ValueResolver}
  alias Jido.Exec.Node.{FlowTarget, Lifecycle, Targets}
  alias Jido.Instruction
  alias Runic.Identity
  alias Runic.Workflow.SingleOutput.{Context, Result}

  @derive {Inspect, only: [:id, :name, :node_path]}
  @enforce_keys [:id, :name, :hash, :definition, :target_versions, :node_path, :terminal?]
  defstruct [:id, :name, :hash, :definition, :target_versions, :node_path, :location, :terminal?]

  @type t :: %__MODULE__{}

  @doc false
  @spec new(keyword()) :: t()
  def new(opts) do
    opts =
      Keyword.validate!(opts, [
        :id,
        :name,
        :definition,
        :location,
        :node_path,
        :target_versions,
        :terminal?
      ])

    id = Keyword.fetch!(opts, :id)
    name = Keyword.fetch!(opts, :name)
    definition = Keyword.fetch!(opts, :definition)

    %__MODULE__{
      id: id,
      name: name,
      hash:
        Identity.digest(:component_definition, %{
          kind: :jido_flow_invoke,
          version: 1,
          id: inspect(id)
        }),
      definition: definition,
      target_versions: Keyword.get_lazy(opts, :target_versions, fn -> Targets.versions(definition) end),
      location: Keyword.get(opts, :location),
      node_path: Keyword.get(opts, :node_path, [name]),
      terminal?: Keyword.get(opts, :terminal?, false)
    }
  end

  @impl Runic.Workflow.SingleOutput
  @doc false
  @spec run(t(), term(), Context.t()) :: Result.t()
  def run(%__MODULE__{} = node, input, %Context{} = context) do
    Lifecycle.run(node, input, context, fn bindings ->
      state = ValueResolver.resolver_state(bindings, context.runtime)

      with :ok <- Targets.compatible(node.target_versions),
           {:ok, params} <- ValueResolver.resolve(node.definition.decision.params, state),
           {:ok, decision, decision_effects, :none} <-
             ActionBoundary.run(node.definition.decision, params, node, context, :invoke_decision) do
        expand(decision, decision_effects, node, context)
      end
    end)
  end

  defp expand(decision, decision_effects, node, context) do
    case ActionBoundary.run(
           node.definition.expander,
           decision,
           node,
           context,
           :invoke_expander,
           :invoke
         ) do
      {:ok, output, effects, :none} ->
        {:ok, output, decision_effects ++ effects}

      {:handoff, input, target} ->
        handoff(input, target, decision_effects, node)

      {:continue, input, target} ->
        continue(input, target, decision_effects, node, context)

      {:error, error} ->
        {:error, error}
    end
  end

  defp handoff(input, target, effects, %{terminal?: true}) do
    with {:ok, instruction} <- Runtime.handoff(target, input) do
      {:ok, instruction, effects, :handoff}
    end
  end

  defp handoff(_input, _target, _effects, node) do
    {:error,
     Error.config_error("handoff must finish the root Flow", %{
       node: node.name,
       reason: :nested_handoff
     })}
  end

  defp continue(input, target, prior, node, context) do
    with {:ok, instruction} <- Instruction.resolve(target, input) do
      run_target(instruction, prior, node, context)
    else
      {:error, error} -> {:error, invoke_error(error, node)}
    end
  end

  defp run_target(%Instruction{kind: :action} = instruction, prior, node, context) do
    case ActionBoundary.run_instruction(instruction, node, context, :invoke_target) do
      {:ok, value, effects, :none} -> {:ok, value, prior ++ effects}
      {:error, error} -> {:error, invoke_error(error, node)}
    end
  end

  defp run_target(%Instruction{kind: :flow} = instruction, prior, node, context) do
    case FlowTarget.run(instruction, context.runtime, node) do
      {:ok, value, effects} -> {:ok, value, prior ++ effects}
      {:error, error} -> {:error, invoke_error(error, node)}
    end
  end

  defp invoke_error(%{details: details} = error, node) when is_map(details) do
    %{error | details: Map.merge(details, %{node: node.name, node_path: node.node_path, phase: :invoke})}
  end

  defp invoke_error(error, _node), do: error
end

defimpl Runic.Identity.Projectable, for: Jido.Exec.Node.Invoke do
  def identity_document(node),
    do: %{kind: :jido_flow_invoke, version: 1, id: inspect(node.id)}
end

defimpl Runic.Component, for: Jido.Exec.Node.Invoke do
  alias Jido.Exec.Node.Invoke
  alias Runic.Workflow

  def connectable?(_node, _other), do: true

  def connect(%Invoke{} = node, parents, workflow) when is_list(parents) do
    join = parents |> Enum.map(& &1.hash) |> Workflow.Join.new()
    workflow = Enum.reduce(parents, workflow, &Workflow.add_step(&2, &1, join))
    connect(node, join, workflow)
  end

  def connect(%Invoke{} = node, parent, workflow) do
    workflow
    |> Workflow.add_step(parent, node)
    |> Workflow.draw_connection(node, node, :component_of, properties: %{kind: :invoke})
    |> Workflow.register_component(node)
  end

  def source(%Invoke{} = node) do
    quote do
      Jido.Exec.Node.Invoke.new(
        id: unquote(Macro.escape(node.id)),
        name: unquote(node.name),
        definition: unquote(Macro.escape(node.definition)),
        target_versions: unquote(Macro.escape(node.target_versions)),
        location: unquote(Macro.escape(node.location)),
        node_path: unquote(Macro.escape(node.node_path)),
        terminal?: unquote(node.terminal?)
      )
    end
  end

  def hash(%Invoke{hash: hash}), do: hash
  def inputs(_node), do: [bindings: [type: :any, doc: "Invoke bindings"]]

  def outputs(_node) do
    [
      value: [type: :any, doc: "Invoke result"],
      effects: [type: :any, doc: "Ordered Invoke effects"],
      control: [type: :any, doc: "Invoke control result"]
    ]
  end
end

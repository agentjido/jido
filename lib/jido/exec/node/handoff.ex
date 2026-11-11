defmodule Jido.Exec.Node.Handoff do
  @moduledoc false

  use Runic.Workflow.SingleOutput, batch_parent: false

  alias Jido.Error
  alias Jido.Exec.{ActionBoundary, Runtime, ValueResolver}
  alias Jido.Exec.Node.{Lifecycle, Targets}
  alias Runic.Identity
  alias Runic.Workflow.SingleOutput.{Context, Result}

  @derive {Inspect, only: [:id, :name, :node_path]}
  @enforce_keys [:id, :name, :hash, :definition, :target_versions, :node_path]
  defstruct [:id, :name, :hash, :definition, :target_versions, :node_path, :location]

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
        :target_versions
      ])

    id = Keyword.fetch!(opts, :id)
    name = Keyword.fetch!(opts, :name)
    definition = Keyword.fetch!(opts, :definition)

    %__MODULE__{
      id: id,
      name: name,
      hash:
        Identity.digest(:component_definition, %{
          kind: :jido_flow_handoff,
          version: 1,
          id: inspect(id)
        }),
      definition: definition,
      target_versions: Keyword.get_lazy(opts, :target_versions, fn -> Targets.versions(definition) end),
      location: Keyword.get(opts, :location),
      node_path: Keyword.get(opts, :node_path, [name])
    }
  end

  @impl Runic.Workflow.SingleOutput
  @doc false
  @spec run(t(), term(), Context.t()) :: Result.t()
  def run(%__MODULE__{} = node, input, %Context{} = context) do
    Lifecycle.run(node, input, context, fn bindings ->
      state = ValueResolver.resolver_state(bindings, context.runtime)
      selector = node.definition.selector

      with :ok <- Targets.compatible(node.target_versions),
           {:ok, params} <- ValueResolver.resolve(selector.params, state) do
        select(selector, params, node, context)
      end
    end)
  end

  defp select(selector, params, node, context) do
    case ActionBoundary.run(selector, params, node, context, :handoff_selector, :handoff) do
      {:handoff, input, target} ->
        with {:ok, instruction} <- Runtime.handoff(target, input) do
          {:ok, instruction, [], :handoff}
        end

      {:error, error} ->
        {:error, error}

      other ->
        returned =
          case other do
            {:ok, value, effects, :none} -> {:ok, value, effects}
            value -> value
          end

        {:error,
         Error.execution_error("Handoff selector must return a handoff control result", %{
           action: selector.target,
           phase: :run,
           return: returned,
           reason: :invalid_handoff_return
         })}
    end
  end
end

defimpl Runic.Identity.Projectable, for: Jido.Exec.Node.Handoff do
  def identity_document(node),
    do: %{kind: :jido_flow_handoff, version: 1, id: inspect(node.id)}
end

defimpl Runic.Component, for: Jido.Exec.Node.Handoff do
  alias Jido.Exec.Node.Handoff
  alias Runic.Workflow

  def connectable?(_node, _other), do: true

  def connect(%Handoff{} = node, parents, workflow) when is_list(parents) do
    join = parents |> Enum.map(& &1.hash) |> Workflow.Join.new()
    workflow = Enum.reduce(parents, workflow, &Workflow.add_step(&2, &1, join))
    connect(node, join, workflow)
  end

  def connect(%Handoff{} = node, parent, workflow) do
    workflow
    |> Workflow.add_step(parent, node)
    |> Workflow.draw_connection(node, node, :component_of, properties: %{kind: :handoff})
    |> Workflow.register_component(node)
  end

  def source(%Handoff{} = node) do
    quote do
      Jido.Exec.Node.Handoff.new(
        id: unquote(Macro.escape(node.id)),
        name: unquote(node.name),
        definition: unquote(Macro.escape(node.definition)),
        target_versions: unquote(Macro.escape(node.target_versions)),
        location: unquote(Macro.escape(node.location)),
        node_path: unquote(Macro.escape(node.node_path))
      )
    end
  end

  def hash(%Handoff{hash: hash}), do: hash
  def inputs(_node), do: [bindings: [type: :any, doc: "Handoff bindings"]]

  def outputs(_node) do
    [
      value: [type: :any, doc: "Successor instruction"],
      effects: [type: :any, doc: "Handoff effects"],
      control: [type: :any, doc: "Handoff control result"]
    ]
  end
end

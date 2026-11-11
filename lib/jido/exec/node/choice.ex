defmodule Jido.Exec.Node.Choice do
  @moduledoc false

  use Runic.Workflow.SingleOutput, batch_parent: false

  alias Jido.Exec.{ActionBoundary, ValueResolver}
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
          kind: :jido_flow_choice,
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

      with :ok <- Targets.compatible(node.target_versions),
           {:ok, call} <- choose(node.definition, state, node.name),
           {:ok, params} <- ValueResolver.resolve(call.params, state) do
        ActionBoundary.call(call, params, node, context, :choice)
      end
    end)
  end

  defp choose(%{options: options, fallback: fallback}, state, component) do
    Enum.reduce_while(options, {:ok, fallback}, fn option, _fallback ->
      case ValueResolver.condition(option.condition, state, component, option.name) do
        {:ok, true} -> {:halt, {:ok, option.call}}
        {:ok, false} -> {:cont, {:ok, fallback}}
        {:error, error} -> {:halt, {:error, error}}
      end
    end)
  end
end

defimpl Runic.Identity.Projectable, for: Jido.Exec.Node.Choice do
  def identity_document(node),
    do: %{kind: :jido_flow_choice, version: 1, id: inspect(node.id)}
end

defimpl Runic.Component, for: Jido.Exec.Node.Choice do
  alias Jido.Exec.Node.Choice
  alias Runic.Workflow

  def connectable?(_node, _other), do: true

  def connect(%Choice{} = node, parents, workflow) when is_list(parents) do
    join = parents |> Enum.map(& &1.hash) |> Workflow.Join.new()
    workflow = Enum.reduce(parents, workflow, &Workflow.add_step(&2, &1, join))
    connect(node, join, workflow)
  end

  def connect(%Choice{} = node, parent, workflow) do
    workflow
    |> Workflow.add_step(parent, node)
    |> Workflow.draw_connection(node, node, :component_of, properties: %{kind: :choice})
    |> Workflow.register_component(node)
  end

  def source(%Choice{} = node) do
    quote do
      Jido.Exec.Node.Choice.new(
        id: unquote(Macro.escape(node.id)),
        name: unquote(node.name),
        definition: unquote(Macro.escape(node.definition)),
        target_versions: unquote(Macro.escape(node.target_versions)),
        location: unquote(Macro.escape(node.location)),
        node_path: unquote(Macro.escape(node.node_path))
      )
    end
  end

  def hash(%Choice{hash: hash}), do: hash
  def inputs(_node), do: [bindings: [type: :any, doc: "Choice bindings"]]

  def outputs(_node) do
    [
      value: [type: :any, doc: "Selected Action value"],
      effects: [type: :any, doc: "Selected Action effects"],
      control: [type: :any, doc: "Choice control result"]
    ]
  end
end

defmodule Jido.Exec.Node.Action do
  @moduledoc false

  use Runic.Workflow.SingleOutput, batch_parent: false

  alias Jido.Exec.{ActionBoundary, ValueResolver}
  alias Jido.Exec.Node.{Lifecycle, Targets}
  alias Runic.Identity
  alias Runic.Workflow.SingleOutput.{Context, Result}

  @derive {Inspect, only: [:id, :name, :node_path]}
  @enforce_keys [:id, :name, :hash, :call, :target_version, :node_path]
  defstruct [:id, :name, :hash, :call, :target_version, :node_path, :location]

  @type t :: %__MODULE__{}

  @doc false
  @spec new(keyword()) :: t()
  def new(opts) do
    opts =
      Keyword.validate!(opts, [
        :id,
        :name,
        :call,
        :location,
        :node_path,
        :target_version
      ])

    id = Keyword.fetch!(opts, :id)
    call = Keyword.fetch!(opts, :call)
    name = Keyword.fetch!(opts, :name)

    %__MODULE__{
      id: id,
      name: name,
      hash:
        Identity.digest(:component_definition, %{
          kind: :jido_flow_action,
          version: 1,
          id: inspect(id)
        }),
      call: call,
      target_version: Keyword.get_lazy(opts, :target_version, fn -> Targets.version(call.target) end),
      location: Keyword.get(opts, :location),
      node_path: Keyword.get(opts, :node_path, [name])
    }
  end

  @impl Runic.Workflow.SingleOutput
  @doc false
  @spec run(t(), term(), Context.t()) :: Result.t()
  def run(%__MODULE__{} = node, input, %Context{} = context) do
    Lifecycle.run(node, input, context, fn bindings ->
      with :ok <- compatible_target(node),
           {:ok, params} <-
             ValueResolver.resolve(
               node.call.params,
               ValueResolver.resolver_state(bindings, context.runtime)
             ) do
        ActionBoundary.call(node.call, params, node, context, :call)
      end
    end)
  end

  defp compatible_target(%__MODULE__{call: %{target: target}, target_version: expected}) do
    Targets.compatible(:action, target, expected)
  end
end

defimpl Runic.Identity.Projectable, for: Jido.Exec.Node.Action do
  def identity_document(node),
    do: %{kind: :jido_flow_action, version: 1, id: inspect(node.id)}
end

defimpl Runic.Component, for: Jido.Exec.Node.Action do
  alias Jido.Exec.Node.Action
  alias Runic.Workflow

  def connectable?(_node, _other), do: true

  def connect(%Action{} = node, parents, workflow) when is_list(parents) do
    join = parents |> Enum.map(& &1.hash) |> Workflow.Join.new()
    workflow = Enum.reduce(parents, workflow, &Workflow.add_step(&2, &1, join))
    connect(node, join, workflow)
  end

  def connect(%Action{} = node, parent, workflow) do
    workflow
    |> Workflow.add_step(parent, node)
    |> Workflow.draw_connection(node, node, :component_of, properties: %{kind: :call})
    |> Workflow.register_component(node)
  end

  def source(%Action{} = node) do
    quote do
      Jido.Exec.Node.Action.new(
        id: unquote(Macro.escape(node.id)),
        name: unquote(node.name),
        call: unquote(Macro.escape(node.call)),
        target_version: unquote(Macro.escape(node.target_version)),
        location: unquote(Macro.escape(node.location)),
        node_path: unquote(Macro.escape(node.node_path))
      )
    end
  end

  def hash(%Action{hash: hash}), do: hash
  def inputs(_node), do: [bindings: [type: :any, doc: "Action parameter bindings"]]

  def outputs(_node) do
    [
      value: [type: :any, doc: "Action value"],
      effects: [type: :any, doc: "Action effects"],
      control: [type: :any, doc: "Action control result"]
    ]
  end
end

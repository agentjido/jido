defmodule Jido.Exec.Node.Map do
  @moduledoc false

  alias Jido.Exec.Fact
  alias Jido.Exec.Fact.LocalValue
  alias Jido.Exec.Frame
  alias Jido.Exec.Node.Action
  alias Jido.Exec.Node.Map.Collection
  alias Runic.Identity
  alias Runic.Workflow
  alias Runic.Workflow.Batch

  @enforce_keys [:id, :name, :hash, :component, :collection, :call, :on_error]
  defstruct [
    :id,
    :name,
    :hash,
    :component,
    :collection,
    :call,
    :on_error,
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
        :collection,
        :call,
        :on_error,
        :location,
        :node_path
      ])

    id = Keyword.fetch!(opts, :id)

    %__MODULE__{
      id: id,
      name: Keyword.fetch!(opts, :name),
      hash: Identity.digest(:component_definition, %{kind: "jido_map", version: 1, id: id}),
      component: Keyword.fetch!(opts, :component),
      collection: Keyword.fetch!(opts, :collection),
      call: Keyword.fetch!(opts, :call),
      on_error: Keyword.fetch!(opts, :on_error),
      location: Keyword.get(opts, :location),
      node_path: Keyword.get(opts, :node_path, [Keyword.fetch!(opts, :component)])
    }
  end

  @doc false
  @spec connect(t(), [term()], Workflow.t()) :: Workflow.t()
  def connect(%__MODULE__{} = node, parents, %Workflow{} = workflow) do
    collection =
      Collection.new(
        id: {node.id, :collection},
        name: internal_name(node, "collection"),
        component: node.component,
        value: node.collection,
        params: node.call.params,
        location: node.location,
        node_path: node.node_path
      )

    flow = %{
      component: node.component,
      mode: {:map, node.on_error},
      location: node.location,
      node_path: node.node_path
    }

    action =
      Action.new(node.call,
        flow: flow,
        id: {node.id, :action},
        name: internal_name(node, "action")
      )

    batch = Runic.batch(action, name: internal_name(node, "batch"))

    projection =
      Runic.Workflow.Step.new(
        name: internal_name(node, "result"),
        hash: Identity.derive(:component_definition, [node.hash, :result]),
        work: &__MODULE__.pass/1
      )

    workflow
    |> connect_from(parents, collection)
    |> Workflow.add(batch, to: collection, log: false)
    |> Workflow.add(projection, to: batch, log: false)
    |> Workflow.draw_connection(node, projection, :component_of, properties: %{kind: :map})
    |> Workflow.register_component(node)
  end

  @doc false
  @spec pass(%Batch.Result{}) :: Frame.t() | Frame.nested_t() | LocalValue.t()
  def pass(%Batch.Result{parent: parent, outcomes: outcomes}) do
    {frame, component} = Fact.unwrap(parent)

    {values, effects} =
      Enum.flat_map_reduce(outcomes, [], fn %{status: :completed, value: result}, effects ->
        case Fact.unwrap(result) do
          {:fail_fast, {:ok, value, requests}} ->
            {[value], [requests | effects]}

          {:collect_errors, {:ok, value, requests}} ->
            {[%{status: :ok, value: value}], [requests | effects]}

          {:collect_errors, {:error, error}} ->
            {[%{status: :error, error: error}], effects}
        end
      end)

    result =
      Frame.put_result(frame, component, values, effects |> Enum.reverse() |> Enum.concat())

    if is_struct(parent, LocalValue), do: Fact.local_value(result), else: result
  end

  defp connect_from(workflow, [], child), do: Workflow.add_step(workflow, child)
  defp connect_from(workflow, [parent], child), do: Workflow.add_step(workflow, parent, child)
  defp connect_from(workflow, parents, child), do: Workflow.add_step(workflow, parents, child)

  defp internal_name(node, kind), do: "__jido_map__/#{node.name}/#{kind}"
end

defimpl Runic.Identity.Projectable, for: Jido.Exec.Node.Map do
  def identity_document(node) do
    %{kind: :jido_map, version: 1, id: inspect(node.id)}
  end
end

defimpl Runic.Component, for: Jido.Exec.Node.Map do
  alias Jido.Exec.Node.Map

  def connectable?(_node, _other), do: true
  def connect(node, to, workflow), do: Map.connect(node, List.wrap(to), workflow)

  def source(node) do
    quote do
      Jido.Exec.Node.Map.new(
        id: unquote(Macro.escape(node.id)),
        name: unquote(node.name),
        component: unquote(node.component),
        collection: unquote(Macro.escape(node.collection)),
        call: unquote(Macro.escape(node.call)),
        on_error: unquote(node.on_error),
        location: unquote(Macro.escape(node.location)),
        node_path: unquote(Macro.escape(node.node_path))
      )
    end
  end

  def hash(node), do: node.hash
  def inputs(_node), do: [items: [type: :any, cardinality: :many]]
  def outputs(node), do: [out: [type: :any, from: "__jido_map__/#{node.name}/result"]]
end

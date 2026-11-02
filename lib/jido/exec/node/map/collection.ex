defmodule Jido.Exec.Node.Map.Collection do
  @moduledoc false

  use Runic.Workflow.SingleOutput, batch_parent: false

  alias Jido.Exec.{Frame, ValueResolver}
  alias Runic.Identity
  alias Runic.Workflow.SingleOutput.{Context, Result}
  alias Runic.Workflow.Batch

  @enforce_keys [:id, :name, :hash, :component, :value, :params]
  defstruct [:id, :name, :hash, :component, :value, :params, :location, :node_path]

  @type t :: %__MODULE__{}

  @doc false
  @spec new(keyword()) :: t()
  def new(opts) do
    opts =
      Keyword.validate!(opts, [:id, :name, :component, :value, :params, :location, :node_path])

    id = Keyword.fetch!(opts, :id)

    %__MODULE__{
      id: id,
      name: Keyword.fetch!(opts, :name),
      hash:
        Identity.digest(:component_definition, %{
          kind: "jido_map_collection",
          version: 1,
          id: id
        }),
      component: Keyword.fetch!(opts, :component),
      value: Keyword.fetch!(opts, :value),
      params: Keyword.fetch!(opts, :params),
      location: Keyword.get(opts, :location),
      node_path: Keyword.get(opts, :node_path, [Keyword.fetch!(opts, :component)])
    }
  end

  @doc false
  @spec resolve(t(), term(), term()) :: {:ok, %Batch.Input{}} | {:error, term()}
  def resolve(%__MODULE__{} = node, input, context) do
    with {:ok, frame} <- Frame.merge(input),
         {:ok, collection} <-
           ValueResolver.resolve(node.value, Frame.resolver_state(frame, context)),
         {:ok, items} <- enumerable(collection) do
      state = Frame.resolver_state(frame, context)

      values =
        items
        |> Enum.with_index()
        |> Enum.map(fn {item, index} ->
          item_id = Frame.item_id(node.id, index)
          item_state = Map.merge(state, %{item: item, item_index: index, item_id: item_id})
          params = resolve_params(node.params, item_state)
          {:jido_map_item, index, item_id, params}
        end)

      {:ok, Batch.input(values, {frame, node.component})}
    end
  end

  defp resolve_params(params, state) do
    case ValueResolver.resolve(params, state) do
      {:error, error} -> {:error, Jido.Flow.Error.to_map(error)}
      result -> result
    end
  end

  defp enumerable(value) do
    if is_nil(Enumerable.impl_for(value)) do
      {:error, ArgumentError.exception("Map collection is not enumerable")}
    else
      {:ok, Enum.to_list(value)}
    end
  end

  @impl Runic.Workflow.SingleOutput
  @doc false
  @spec run(t(), term(), Context.t()) :: Result.t()
  def run(%__MODULE__{} = node, input, %Context{} = context) do
    case resolve(node, Jido.Exec.Fact.unwrap(input), context.runtime) do
      {:ok, value} ->
        Jido.Exec.Fact.result(input, context, value)

      {:error, error} ->
        Result.failure(
          Jido.Exec.Source.attach(error, node.location, %{
            node: node.component,
            node_path: node.node_path
          })
        )
    end
  end
end

defimpl Runic.Identity.Projectable, for: Jido.Exec.Node.Map.Collection do
  def identity_document(node) do
    %{kind: :jido_map_collection, version: 1, id: inspect(node.id)}
  end
end

defimpl Runic.Component, for: Jido.Exec.Node.Map.Collection do
  def connectable?(_node, _other), do: true
  def connect(node, to, workflow), do: Runic.Workflow.add_step(workflow, to, node)

  def source(node) do
    quote do
      Jido.Exec.Node.Map.Collection.new(
        id: unquote(Macro.escape(node.id)),
        name: unquote(node.name),
        component: unquote(node.component),
        value: unquote(Macro.escape(node.value)),
        params: unquote(Macro.escape(node.params)),
        location: unquote(Macro.escape(node.location)),
        node_path: unquote(Macro.escape(node.node_path))
      )
    end
  end

  def hash(node), do: node.hash
  def inputs(_node), do: [in: [type: :any]]
  def outputs(_node), do: [out: [type: :any, cardinality: :many]]
end

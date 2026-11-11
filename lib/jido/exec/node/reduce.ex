defmodule Jido.Exec.Node.Reduce do
  @moduledoc false

  use Runic.Workflow.SingleOutput, batch_parent: false

  alias Jido.Error
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
          kind: :jido_flow_reduce,
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
           {:ok, collection} <- ValueResolver.resolve(node.definition.collection, state),
           {:ok, items} <- enumerable(collection, node),
           {:ok, initial} <- ValueResolver.resolve(node.definition.initial, state),
           :ok <- validate_initial(initial, node) do
        items
        |> Enum.with_index()
        |> Enum.reduce_while({:ok, initial, []}, fn {item, index}, {:ok, accumulator, effect_groups} ->
          case run_item(item, index, accumulator, state, node, context) do
            {:ok, value, effects} -> {:cont, {:ok, value, [effects | effect_groups]}}
            {:error, error} -> {:halt, {:error, error}}
          end
        end)
        |> reduce_result()
      end
    end)
  end

  defp run_item(item, index, accumulator, state, node, context) do
    item_id = item_id(node.id, index)

    resolver =
      Map.merge(state, %{
        item: item,
        item_index: index,
        item_id: item_id,
        accumulator: accumulator
      })

    result =
      with {:ok, params} <- ValueResolver.resolve(node.definition.call.params, resolver),
           {:ok, value, effects} <-
             ActionBoundary.call(node.definition.call, params, node, context, {:reduce, index}) do
        {:ok, value, effects}
      end

    case result do
      {:ok, _value, _effects} = success ->
        success

      {:error, error} ->
        {:error, position_error(error, node, %{item_index: index, item_id: item_id})}
    end
  end

  defp reduce_result({:ok, value, effect_groups}),
    do: {:ok, value, effect_groups |> Enum.reverse() |> Enum.concat()}

  defp reduce_result({:error, error}), do: {:error, error}

  defp validate_initial(value, _node)
       when is_map(value) and not is_struct(value),
       do: :ok

  defp validate_initial(%Jido.Action.Output{}, _node), do: :ok

  defp validate_initial(value, node) do
    {:error,
     Error.execution_error("reduce initial value must be a map or Jido.Action.Output", %{
       node: node.name,
       phase: :reduce_initial,
       value: value,
       retry: false
     })}
  end

  defp enumerable(value, node) do
    if Enumerable.impl_for(value) do
      {:ok, Enum.to_list(value)}
    else
      {:error,
       Error.execution_error("Reduce collection is not enumerable", %{
         node: node.name,
         phase: :reduce_collection,
         value: value,
         retry: false
       })}
    end
  end

  defp item_id(owner_id, index) do
    {owner_id, index}
    |> :erlang.term_to_binary([:deterministic])
    |> then(&:crypto.hash(:sha256, &1))
    |> Base.encode16(case: :lower)
  end

  defp position_error(%{details: details} = error, node, extra) when is_map(details) do
    %{error | details: details |> Map.merge(extra) |> Map.put_new(:node, node.name)}
  end

  defp position_error(error, _node, _extra), do: error
end

defimpl Runic.Identity.Projectable, for: Jido.Exec.Node.Reduce do
  def identity_document(node),
    do: %{kind: :jido_flow_reduce, version: 1, id: inspect(node.id)}
end

defimpl Runic.Component, for: Jido.Exec.Node.Reduce do
  alias Jido.Exec.Node.Reduce
  alias Runic.Workflow

  def connectable?(_node, _other), do: true

  def connect(%Reduce{} = node, parents, workflow) when is_list(parents) do
    join = parents |> Enum.map(& &1.hash) |> Workflow.Join.new()
    workflow = Enum.reduce(parents, workflow, &Workflow.add_step(&2, &1, join))
    connect(node, join, workflow)
  end

  def connect(%Reduce{} = node, parent, workflow) do
    workflow
    |> Workflow.add_step(parent, node)
    |> Workflow.draw_connection(node, node, :component_of, properties: %{kind: :reduce})
    |> Workflow.register_component(node)
  end

  def source(%Reduce{} = node) do
    quote do
      Jido.Exec.Node.Reduce.new(
        id: unquote(Macro.escape(node.id)),
        name: unquote(node.name),
        definition: unquote(Macro.escape(node.definition)),
        target_versions: unquote(Macro.escape(node.target_versions)),
        location: unquote(Macro.escape(node.location)),
        node_path: unquote(Macro.escape(node.node_path))
      )
    end
  end

  def hash(%Reduce{hash: hash}), do: hash
  def inputs(_node), do: [bindings: [type: :any, doc: "Reduce bindings"]]

  def outputs(_node) do
    [
      value: [type: :any, doc: "Final Reduce accumulator"],
      effects: [type: :any, doc: "Ordered Reduce effects"],
      control: [type: :any, doc: "Reduce control result"]
    ]
  end
end

defmodule Jido.Exec.Node.Map do
  @moduledoc false

  use Runic.Workflow.SingleOutput, batch_parent: false

  alias Jido.Error
  alias Jido.Exec.{ActionBoundary, ValueResolver}
  alias Jido.Exec.Result, as: ExecResult
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
          kind: :jido_flow_map,
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
           {:ok, items} <- enumerable(collection, node) do
        items
        |> Enum.with_index()
        |> concurrent_map(context.runtime, node.definition.on_error == :fail_fast, fn {item, index} ->
          run_item(item, index, state, node, context)
        end)
        |> Enum.map(fn
          {:task_exit, {_item, index}, reason} ->
            item_id = item_id(node.id, index)
            error = ExecResult.normalize({:task_crashed, reason})
            {:error, position_error(error, node, %{item_index: index, item_id: item_id})}

          outcome ->
            outcome
        end)
        |> map_result(node.definition.on_error, node.definition.call.target, node)
      end
    end)
  end

  defp run_item(item, index, state, node, context) do
    item_id = item_id(node.id, index)
    resolver = Map.merge(state, %{item: item, item_index: index, item_id: item_id})

    case ValueResolver.resolve(node.definition.call.params, resolver) do
      {:ok, params} ->
        case ActionBoundary.call(node.definition.call, params, node, context, {:map, index}) do
          {:ok, value, effects} -> {:ok, value, effects}
          {:error, error} -> {:error, position_error(error, node, %{item_index: index, item_id: item_id})}
        end

      {:error, error} ->
        {:reference_error, error, index, item_id}
    end
  end

  defp map_result(outcomes, :fail_fast, _target, node) do
    case Enum.find(outcomes, &failed_outcome?/1) do
      {:error, error} ->
        {:error, error}

      {:reference_error, error, index, item_id} ->
        {:error, position_error(error, node, %{item_index: index, item_id: item_id})}

      nil ->
        values = Enum.map(outcomes, fn {:ok, value, _effects} -> value end)
        effects = Enum.flat_map(outcomes, fn {:ok, _value, effects} -> effects end)
        {:ok, values, effects}
    end
  end

  defp map_result(outcomes, :collect_errors, target, node) do
    {values, effect_groups} =
      Enum.map_reduce(outcomes, [], fn
        {:ok, value, effects}, groups ->
          {%{status: :ok, value: value}, [effects | groups]}

        {:reference_error, error, _index, _item_id}, groups ->
          {%{status: :error, error: collected_error(error)}, groups}

        {:error, error}, groups ->
          {%{status: :error, error: collected_error(error, %{target: target, node: node.name})}, groups}
      end)

    {:ok, values, effect_groups |> Enum.reverse() |> Enum.concat()}
  end

  defp enumerable(value, node) do
    if Enumerable.impl_for(value) do
      {:ok, Enum.to_list(value)}
    else
      {:error,
       Error.execution_error("Map collection is not enumerable", %{
         node: node.name,
         phase: :map_collection,
         value: value,
         retry: false
       })}
    end
  end

  defp concurrent_map(items, runtime, fail_fast?, fun) do
    max_concurrency = Map.get(runtime, :__jido_exec_max_concurrency__, 1)

    if max_concurrency > 1 and length(items) > 1 do
      items
      |> Task.async_stream(fun,
        ordered: true,
        max_concurrency: max_concurrency,
        timeout: :infinity
      )
      |> Enum.zip(items)
      |> Enum.map(fn
        {{:ok, value}, _item} -> value
        {{:exit, reason}, item} -> {:task_exit, item, reason}
      end)
    else
      serial_map(items, fail_fast?, fun)
    end
  end

  defp serial_map(items, true, fun) do
    items
    |> Enum.reduce_while([], fn item, outcomes ->
      outcome = fun.(item)

      if failed_outcome?(outcome),
        do: {:halt, [outcome | outcomes]},
        else: {:cont, [outcome | outcomes]}
    end)
    |> Enum.reverse()
  end

  defp serial_map(items, false, fun), do: Enum.map(items, fun)

  defp failed_outcome?({:error, _error}), do: true
  defp failed_outcome?({:reference_error, _error, _index, _item_id}), do: true
  defp failed_outcome?(_outcome), do: false

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

  defp collected_error(error, extra \\ %{}) do
    error
    |> Error.to_map()
    |> Map.update!(:details, fn details -> details |> Map.merge(extra) |> Map.delete(:stacktrace) end)
  end
end

defimpl Runic.Identity.Projectable, for: Jido.Exec.Node.Map do
  def identity_document(node),
    do: %{kind: :jido_flow_map, version: 1, id: inspect(node.id)}
end

defimpl Runic.Component, for: Jido.Exec.Node.Map do
  alias Jido.Exec.Node.Map
  alias Runic.Workflow

  def connectable?(_node, _other), do: true

  def connect(%Map{} = node, parents, workflow) when is_list(parents) do
    join = parents |> Enum.map(& &1.hash) |> Workflow.Join.new()
    workflow = Enum.reduce(parents, workflow, &Workflow.add_step(&2, &1, join))
    connect(node, join, workflow)
  end

  def connect(%Map{} = node, parent, workflow) do
    workflow
    |> Workflow.add_step(parent, node)
    |> Workflow.draw_connection(node, node, :component_of, properties: %{kind: :map})
    |> Workflow.register_component(node)
  end

  def source(%Map{} = node) do
    quote do
      Jido.Exec.Node.Map.new(
        id: unquote(Macro.escape(node.id)),
        name: unquote(node.name),
        definition: unquote(Macro.escape(node.definition)),
        target_versions: unquote(Macro.escape(node.target_versions)),
        location: unquote(Macro.escape(node.location)),
        node_path: unquote(Macro.escape(node.node_path))
      )
    end
  end

  def hash(%Map{hash: hash}), do: hash
  def inputs(_node), do: [bindings: [type: :any, doc: "Map bindings"]]

  def outputs(_node) do
    [
      value: [type: :any, doc: "Ordered Map results"],
      effects: [type: :any, doc: "Ordered Map effects"],
      control: [type: :any, doc: "Map control result"]
    ]
  end
end

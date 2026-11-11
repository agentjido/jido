defmodule Jido.Exec.Node.Parallel do
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
          kind: :jido_flow_parallel,
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

      with :ok <- Targets.compatible(node.target_versions) do
        node.definition.actions
        |> Enum.with_index()
        |> concurrent_map(context.runtime, fn {action, index} ->
          run_action(action, index, state, node, context)
        end)
        |> Enum.map(fn
          {:task_exit, {action, index}, reason} ->
            error = ExecResult.normalize({:task_crashed, reason})
            {:error, action.name, parallel_error(error, node, action, index)}

          outcome ->
            outcome
        end)
        |> parallel_result(node.definition.on_error)
      end
    end)
  end

  defp run_action(action, index, state, node, context) do
    case ValueResolver.resolve(action.call.params, state) do
      {:ok, params} ->
        case ActionBoundary.call(action.call, params, node, context, {:parallel, action.name}) do
          {:ok, value, effects} -> {:ok, action.name, value, effects}
          {:error, error} -> {:error, action.name, parallel_error(error, node, action, index)}
        end

      {:error, error} ->
        {:error, action.name, parallel_error(error, node, action, index)}
    end
  end

  defp parallel_result(outcomes, :fail_fast) do
    case Enum.find(outcomes, &match?({:error, _, _}, &1)) do
      {:error, _name, error} ->
        {:error, error}

      nil ->
        values = Enum.map(outcomes, fn {:ok, name, value, _effects} -> %{name: name, value: value} end)
        effects = Enum.flat_map(outcomes, fn {:ok, _name, _value, effects} -> effects end)
        {:ok, values, effects}
    end
  end

  defp parallel_result(outcomes, :collect_errors) do
    {values, effect_groups} =
      Enum.map_reduce(outcomes, [], fn
        {:ok, name, value, effects}, groups ->
          {%{name: name, status: :ok, value: value}, [effects | groups]}

        {:error, name, error}, groups ->
          {%{name: name, status: :error, error: collected_error(error)}, groups}
      end)

    {:ok, values, effect_groups |> Enum.reverse() |> Enum.concat()}
  end

  defp concurrent_map(items, runtime, fun) do
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
      Enum.map(items, fun)
    end
  end

  defp parallel_error(error, node, action, index) do
    position_error(error, node, %{
      action_index: index,
      action_name: action.name,
      target: action.call.target,
      node_path: node.node_path ++ [action.name]
    })
  end

  defp position_error(%{details: details} = error, node, extra) when is_map(details) do
    %{error | details: details |> Map.merge(extra) |> Map.put_new(:node, node.name)}
  end

  defp position_error(error, _node, _extra), do: error

  defp collected_error(error) do
    error
    |> Error.to_map()
    |> Map.update!(:details, &Map.delete(&1, :stacktrace))
  end
end

defimpl Runic.Identity.Projectable, for: Jido.Exec.Node.Parallel do
  def identity_document(node),
    do: %{kind: :jido_flow_parallel, version: 1, id: inspect(node.id)}
end

defimpl Runic.Component, for: Jido.Exec.Node.Parallel do
  alias Jido.Exec.Node.Parallel
  alias Runic.Workflow

  def connectable?(_node, _other), do: true

  def connect(%Parallel{} = node, parents, workflow) when is_list(parents) do
    join = parents |> Enum.map(& &1.hash) |> Workflow.Join.new()
    workflow = Enum.reduce(parents, workflow, &Workflow.add_step(&2, &1, join))
    connect(node, join, workflow)
  end

  def connect(%Parallel{} = node, parent, workflow) do
    workflow
    |> Workflow.add_step(parent, node)
    |> Workflow.draw_connection(node, node, :component_of, properties: %{kind: :parallel})
    |> Workflow.register_component(node)
  end

  def source(%Parallel{} = node) do
    quote do
      Jido.Exec.Node.Parallel.new(
        id: unquote(Macro.escape(node.id)),
        name: unquote(node.name),
        definition: unquote(Macro.escape(node.definition)),
        target_versions: unquote(Macro.escape(node.target_versions)),
        location: unquote(Macro.escape(node.location)),
        node_path: unquote(Macro.escape(node.node_path))
      )
    end
  end

  def hash(%Parallel{hash: hash}), do: hash
  def inputs(_node), do: [bindings: [type: :any, doc: "Parallel bindings"]]

  def outputs(_node) do
    [
      value: [type: :any, doc: "Ordered Parallel results"],
      effects: [type: :any, doc: "Ordered Parallel effects"],
      control: [type: :any, doc: "Parallel control result"]
    ]
  end
end

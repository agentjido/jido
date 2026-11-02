defmodule Jido.Exec.Node.Parallel do
  @moduledoc false

  use Runic.Workflow.SingleOutput, batch_parent: false

  alias Jido.Exec.{Fact, Frame}
  alias Jido.Exec.Node.Action
  alias Runic.Identity
  alias Runic.Workflow
  alias Runic.Workflow.SingleOutput.{Context, Result}

  @enforce_keys [:id, :name, :hash, :component, :actions, :on_error]
  defstruct [:id, :name, :hash, :component, :actions, :on_error, :location, :node_path]

  @type t :: %__MODULE__{}

  @doc false
  @spec new(keyword()) :: t()
  def new(opts) do
    opts =
      Keyword.validate!(opts, [
        :id,
        :name,
        :component,
        :actions,
        :on_error,
        :location,
        :node_path
      ])

    id = Keyword.fetch!(opts, :id)

    %__MODULE__{
      id: id,
      name: Keyword.fetch!(opts, :name),
      hash: Identity.digest(:component_definition, %{kind: "jido_parallel", version: 1, id: id}),
      component: Keyword.fetch!(opts, :component),
      actions: Keyword.fetch!(opts, :actions),
      on_error: Keyword.fetch!(opts, :on_error),
      location: Keyword.get(opts, :location),
      node_path: Keyword.get(opts, :node_path, [Keyword.fetch!(opts, :component)])
    }
  end

  @doc false
  @spec connect(t(), [term()], Workflow.t()) :: Workflow.t()
  def connect(%__MODULE__{} = node, parents, %Workflow{} = workflow) do
    actions =
      node.actions
      |> Enum.with_index()
      |> Enum.map(fn {action, index} ->
        flow = %{
          component: node.component,
          mode: {:parallel, node.on_error, index, action.name},
          params: action.call.params,
          location: node.location,
          node_path: node.node_path ++ [action.name]
        }

        Action.new(action.call,
          flow: flow,
          id: {node.id, :action, index, action.name},
          name: internal_name(node, "action", index, action.name)
        )
      end)

    join = actions |> Enum.map(& &1.hash) |> Runic.Workflow.Join.new()

    {workflow, parent} = join_parents(workflow, parents)

    workflow = Enum.reduce(actions, workflow, &connect_from(&2, parent, &1))

    workflow = Enum.reduce(actions, workflow, &Workflow.add_step(&2, &1, join))

    workflow
    |> Workflow.add_step(join, node)
    |> Workflow.draw_connection(node, node, :component_of, properties: %{kind: :parallel})
    |> Workflow.register_component(node)
  end

  @impl Runic.Workflow.SingleOutput
  @doc false
  @spec run(t(), term(), Context.t()) :: Result.t()
  def run(%__MODULE__{} = node, input, %Context{} = context) do
    case complete(node, Fact.unwrap(input)) do
      {:ok, frame} ->
        Fact.result(input, context, frame)

      {:error, error} ->
        Result.failure(
          Jido.Exec.Source.attach(error, node.location, %{
            node: node.component,
            node_path: node.node_path
          })
        )
    end
  end

  defp complete(node, outcomes) when is_list(outcomes) do
    with :ok <- validate_outcomes(node, outcomes),
         {:ok, frame} <- outcomes |> Enum.map(&elem(&1, 3)) |> Frame.merge() do
      {results, effects} = results(node.on_error, outcomes)
      {:ok, Frame.put_result(frame, node.component, results, effects)}
    end
  end

  defp complete(_node, value), do: invalid_outcomes(value)

  defp validate_outcomes(node, outcomes) do
    expected = Enum.with_index(node.actions, fn action, index -> {index, action.name} end)
    actual = Enum.map(outcomes, &outcome_identity(&1, node.on_error))

    if actual == expected, do: :ok, else: invalid_outcomes(outcomes)
  end

  defp outcome_identity(
         {:jido_parallel_action, index, name, _frame, {:ok, _value, effects}},
         _on_error
       ) do
    if is_list(effects) and not List.improper?(effects), do: {index, name}, else: :invalid
  end

  defp outcome_identity(
         {:jido_parallel_action, index, name, _frame, {:error, _error}},
         :collect_errors
       ),
       do: {index, name}

  defp outcome_identity(_outcome, _on_error), do: :invalid

  defp results(:fail_fast, outcomes) do
    Enum.map_reduce(outcomes, [], fn
      {:jido_parallel_action, _index, name, _frame, {:ok, value, action_effects}}, effects ->
        {%{name: name, value: value}, [action_effects | effects]}
    end)
    |> ordered_effects()
  end

  defp results(:collect_errors, outcomes) do
    Enum.map_reduce(outcomes, [], fn
      {:jido_parallel_action, _index, name, _frame, {:ok, value, action_effects}}, effects ->
        {%{name: name, status: :ok, value: value}, [action_effects | effects]}

      {:jido_parallel_action, _index, name, _frame, {:error, error}}, effects ->
        {%{name: name, status: :error, error: error}, effects}
    end)
    |> ordered_effects()
  end

  defp ordered_effects({results, reversed_effects}),
    do: {results, reversed_effects |> Enum.reverse() |> Enum.concat()}

  defp invalid_outcomes(value) do
    {:error,
     Jido.Flow.Error.execution_error("Parallel received invalid Action outcomes", %{
       reason: :invalid_parallel_outcomes,
       value: value
     })}
  end

  defp join_parents(workflow, []), do: {workflow, nil}
  defp join_parents(workflow, [parent]), do: {workflow, parent}

  defp join_parents(workflow, parents) do
    join = parents |> Enum.map(& &1.hash) |> Runic.Workflow.Join.new()
    workflow = Enum.reduce(parents, workflow, &Workflow.add_step(&2, &1, join))
    {workflow, join}
  end

  defp connect_from(workflow, nil, child), do: Workflow.add_step(workflow, child)
  defp connect_from(workflow, parent, child), do: Workflow.add_step(workflow, parent, child)

  defp internal_name(node, kind, index, name) do
    index = index |> Integer.to_string() |> String.pad_leading(10, "0")
    "__jido_parallel__/#{node.name}/#{kind}/#{index}/#{name}"
  end
end

defimpl Runic.Identity.Projectable, for: Jido.Exec.Node.Parallel do
  def identity_document(node) do
    %{kind: :jido_parallel, version: 1, id: inspect(node.id)}
  end
end

defimpl Runic.Component, for: Jido.Exec.Node.Parallel do
  alias Jido.Exec.Node.Parallel

  def connectable?(_node, _other), do: true
  def connect(node, to, workflow), do: Parallel.connect(node, List.wrap(to), workflow)

  def source(node) do
    quote do
      Jido.Exec.Node.Parallel.new(
        id: unquote(Macro.escape(node.id)),
        name: unquote(node.name),
        component: unquote(node.component),
        actions: unquote(Macro.escape(node.actions)),
        on_error: unquote(node.on_error),
        location: unquote(Macro.escape(node.location)),
        node_path: unquote(Macro.escape(node.node_path))
      )
    end
  end

  def hash(node), do: node.hash
  def inputs(_node), do: [in: [type: :any]]
  def outputs(_node), do: [out: [type: :any]]
end

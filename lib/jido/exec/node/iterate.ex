defmodule Jido.Exec.Node.Iterate do
  @moduledoc false

  use Runic.Workflow.SingleOutput, batch_parent: false

  alias Jido.Action.Validation, as: ActionValidation
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
          kind: :jido_flow_iterate,
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
      resolver = ValueResolver.resolver_state(bindings, context.runtime)

      with :ok <- Targets.compatible(node.target_versions),
           {:ok, initial} <- ValueResolver.resolve(node.definition.state.initial, resolver),
           {:ok, initial} <- validate_state(node, initial, :initial, 0) do
        iterate(node, context, resolver, initial, 0, nil, [])
      end
    end)
  end

  defp iterate(node, context, resolver, state, completed, body, effect_groups) do
    with {:ok, complete?} <- complete?(node, resolver, state, completed, body) do
      cond do
        complete? ->
          value = %{
            kind: :jido_flow_iterate_result,
            iterations: completed,
            state: state,
            output: body
          }

          {:ok, value, effect_groups |> Enum.reverse() |> Enum.concat()}

        completed >= node.definition.max_iterations ->
          exhausted(node, state, completed)

        true ->
          run_iteration(node, context, resolver, state, completed, body, effect_groups)
      end
    end
  end

  defp run_iteration(node, context, resolver, state, completed, body, effect_groups) do
    iteration_resolver =
      Map.merge(resolver, %{
        iterate_state: state,
        iteration_index: completed,
        body_result: body
      })

    result =
      with {:ok, params} <- ValueResolver.resolve(node.definition.call.params, iteration_resolver),
           {:ok, output, effects} <-
             ActionBoundary.call(node.definition.call, params, node, context, {:iterate, completed}),
           {:ok, candidate} <-
             ValueResolver.resolve(
               node.definition.state.update,
               Map.put(iteration_resolver, :body_result, output)
             ),
           {:ok, next_state} <- validate_state(node, candidate, :update, completed + 1) do
        iterate(
          node,
          context,
          resolver,
          next_state,
          completed + 1,
          output,
          [effects | effect_groups]
        )
      end

    case result do
      {:error, error} ->
        {:error,
         position_error(error, node, %{
           iteration_index: completed,
           state_revision: completed
         })}

      other ->
        other
    end
  end

  defp complete?(node, resolver, state, completed, body) do
    resolver =
      Map.merge(resolver, %{
        iterate_state: state,
        iteration_index: completed,
        body_result: body
      })

    case ValueResolver.resolve(node.definition.completion, resolver) do
      {:ok, value} when is_boolean(value) ->
        {:ok, value}

      {:ok, value} ->
        {:error,
         Error.execution_error("invalid iterator completion condition operands", %{
           phase: :iterate_completion,
           node: node.name,
           iterations: completed,
           reason: :invalid_boolean_operand,
           value: value,
           expression_path: [],
           retry: false
         })}

      {:error, error} ->
        {:error,
         position_error(error, node, %{
           phase: :iterate_completion,
           iterations: completed
         })}
    end
  end

  defp validate_state(node, value, phase, revision) do
    details = %{
      node: node.name,
      phase: if(phase == :initial, do: :iterate_state_initial, else: :iterate_state_update),
      state_revision: revision,
      retry: false
    }

    if is_map(value) and not is_struct(value) do
      validate_state_schema(node.definition.state.schema, value, details)
    else
      message =
        if phase == :initial,
          do: "iterator initial state must resolve to a plain map",
          else: "iterator state update must resolve to a plain map"

      {:error,
       Error.execution_error(
         message,
         Map.merge(details, %{reason: :not_a_plain_map, value: value})
       )}
    end
  end

  defp validate_state_schema(schema, value, details) do
    case ActionValidation.parse_preserving_shape(schema, value, details) do
      {:ok, validated} when is_map(validated) and not is_struct(validated) ->
        {:ok, validated}

      {:ok, validated} ->
        {:error,
         Error.execution_error(
           "iterator state schema must return a plain map",
           Map.merge(details, %{reason: :not_a_plain_map, value: validated})
         )}

      {:error, _reason} ->
        {:error, Error.validation_error("iterator state schema validation failed", details)}
    end
  end

  defp exhausted(node, state, completed) do
    {:error,
     Error.execution_error("flow iterator exhausted maximum iterations", %{
       phase: :iterate_exhaustion,
       node: node.name,
       max_iterations: node.definition.max_iterations,
       completed_iterations: completed,
       state_revision: completed,
       state: state,
       retry: false
     })}
  end

  defp position_error(%{details: details} = error, node, extra) when is_map(details) do
    error = %{error | details: details |> Map.merge(extra) |> Map.put_new(:node, node.name)}

    case {error, extra} do
      {%Error.ExecutionError{}, %{phase: phase}} -> %{error | phase: phase}
      _other -> error
    end
  end

  defp position_error(error, _node, _extra), do: error
end

defimpl Runic.Identity.Projectable, for: Jido.Exec.Node.Iterate do
  def identity_document(node),
    do: %{kind: :jido_flow_iterate, version: 1, id: inspect(node.id)}
end

defimpl Runic.Component, for: Jido.Exec.Node.Iterate do
  alias Jido.Exec.Node.Iterate
  alias Runic.Workflow

  def connectable?(_node, _other), do: true

  def connect(%Iterate{} = node, parents, workflow) when is_list(parents) do
    join = parents |> Enum.map(& &1.hash) |> Workflow.Join.new()
    workflow = Enum.reduce(parents, workflow, &Workflow.add_step(&2, &1, join))
    connect(node, join, workflow)
  end

  def connect(%Iterate{} = node, parent, workflow) do
    workflow
    |> Workflow.add_step(parent, node)
    |> Workflow.draw_connection(node, node, :component_of, properties: %{kind: :iterate})
    |> Workflow.register_component(node)
  end

  def source(%Iterate{} = node) do
    quote do
      Jido.Exec.Node.Iterate.new(
        id: unquote(Macro.escape(node.id)),
        name: unquote(node.name),
        definition: unquote(Macro.escape(node.definition)),
        target_versions: unquote(Macro.escape(node.target_versions)),
        location: unquote(Macro.escape(node.location)),
        node_path: unquote(Macro.escape(node.node_path))
      )
    end
  end

  def hash(%Iterate{hash: hash}), do: hash
  def inputs(_node), do: [bindings: [type: :any, doc: "Iterate bindings"]]

  def outputs(_node) do
    [
      value: [type: :any, doc: "Iterate result"],
      effects: [type: :any, doc: "Ordered Iterate effects"],
      control: [type: :any, doc: "Iterate control result"]
    ]
  end
end

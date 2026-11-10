defmodule Jido.Exec.Node.Choice do
  @moduledoc false

  use Runic.Workflow.SingleOutput, batch_parent: false

  alias Jido.Exec.Node.Action
  alias Jido.Exec.Node.Choice.{Branch, Selector}
  alias Runic.Identity
  alias Runic.Workflow.SingleOutput.{Context, Result}
  alias Runic.Workflow

  @enforce_keys [:id, :name, :hash, :component, :options, :fallback]
  defstruct [:id, :name, :hash, :component, :options, :fallback, :location, :node_path]

  @type t :: %__MODULE__{}

  @doc false
  @spec new(keyword()) :: t()
  def new(opts) do
    opts =
      Keyword.validate!(opts, [:id, :name, :component, :options, :fallback, :location, :node_path])

    id = Keyword.fetch!(opts, :id)
    name = Keyword.fetch!(opts, :name)

    %__MODULE__{
      id: id,
      name: name,
      hash: Identity.digest(:component_definition, %{kind: "jido_choice", version: 1, id: id}),
      component: Keyword.fetch!(opts, :component),
      options: Keyword.fetch!(opts, :options),
      fallback: Keyword.fetch!(opts, :fallback),
      location: Keyword.get(opts, :location),
      node_path: Keyword.get(opts, :node_path, [Keyword.fetch!(opts, :component)])
    }
  end

  @doc false
  @spec connect(t(), [term()], Workflow.t()) :: Workflow.t()
  def connect(%__MODULE__{} = node, parents, %Workflow{} = workflow) do
    paths = Enum.map(node.options, &{{:option, &1.name}, &1.call}) ++ [{:fallback, node.fallback}]

    selector =
      Selector.new(
        id: {node.id, :selector},
        name: internal_name(node, "selector", "route"),
        component: node.component,
        options: node.options,
        location: node.location,
        node_path: node.node_path
      )

    workflow = connect_from(workflow, parents, selector)

    workflow =
      Enum.reduce(paths, workflow, fn {route, call}, current ->
        path = route_path(route)

        branch =
          Branch.new(
            id: {node.id, :branch, route},
            name: internal_name(node, "branch", path),
            component: node.component,
            option: route,
            location: node.location,
            node_path: node.node_path
          )

        condition =
          condition({node.id, :condition, route}, internal_name(node, "if", path))

        flow = %{
          component: node.component,
          mode: :choice,
          location: node.location,
          node_path: node.node_path
        }

        action =
          Action.new(call,
            flow: flow,
            id: {node.id, :action, route},
            name: internal_name(node, "action", path)
          )

        current
        |> Workflow.add_step(selector, branch)
        |> Workflow.add_step(branch, condition)
        |> Workflow.add_step(condition, action)
        |> Workflow.add_step(action, node)
      end)

    workflow
    |> Workflow.draw_connection(node, node, :component_of, properties: %{kind: :choice})
    |> Workflow.register_component(node)
  end

  @doc false
  @spec condition(term(), term()) :: struct()
  def condition(id, name) do
    hash =
      Identity.digest(:component_definition, %{kind: "jido_choice_condition", version: 1, id: id})

    source =
      quote do
        Jido.Exec.Node.Choice.condition(unquote(Macro.escape(id)), unquote(name))
      end

    %Runic.Workflow.Condition{
      name: name,
      hash: hash,
      work: &__MODULE__.selected?/1,
      arity: 1,
      closure: Runic.Closure.new(source, %{}, nil),
      meta_refs: []
    }
  end

  @doc false
  @spec selected?(term()) :: boolean()
  def selected?({:jido_choice_branch, true, _frame}), do: true
  def selected?(_value), do: false

  @doc false
  @spec pass(term()) :: {:ok, term()}
  def pass({:jido_flow_frame, 1, _input, _results, _effects} = frame), do: {:ok, frame}

  def pass({:jido_nested_flow_frame, 1, _parent, _child} = frame), do: {:ok, frame}

  defp connect_from(workflow, [], child), do: Workflow.add_step(workflow, child)
  defp connect_from(workflow, [parent], child), do: Workflow.add_step(workflow, parent, child)
  defp connect_from(workflow, parents, child), do: Workflow.add_step(workflow, parents, child)

  defp internal_name(node, kind, path), do: "__jido_choice__/#{node.name}/#{kind}/#{path}"
  defp route_path({:option, name}), do: "option/#{name}"
  defp route_path(:fallback), do: "fallback"
  @impl Runic.Workflow.SingleOutput
  @doc false
  @spec run(t(), term(), Context.t()) :: Result.t()
  def run(%__MODULE__{}, input, %Context{} = context) do
    {:ok, value} = pass(Jido.Exec.Fact.unwrap(input))
    Jido.Exec.Fact.result(input, context, value)
  end
end

defimpl Runic.Identity.Projectable, for: Jido.Exec.Node.Choice do
  def identity_document(node) do
    %{kind: :jido_choice, version: 1, id: inspect(node.id)}
  end
end

defimpl Runic.Component, for: Jido.Exec.Node.Choice do
  alias Jido.Exec.Node.Choice

  def connectable?(_node, _other), do: true
  def connect(node, to, workflow), do: Choice.connect(node, List.wrap(to), workflow)

  def source(node) do
    quote do
      Jido.Exec.Node.Choice.new(
        id: unquote(Macro.escape(node.id)),
        name: unquote(node.name),
        component: unquote(node.component),
        options: unquote(Macro.escape(node.options)),
        fallback: unquote(Macro.escape(node.fallback)),
        location: unquote(Macro.escape(node.location)),
        node_path: unquote(Macro.escape(node.node_path))
      )
    end
  end

  def hash(node), do: node.hash
  def inputs(_node), do: [in: [type: :any]]
  def outputs(_node), do: [out: [type: :any]]
end

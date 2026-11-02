defmodule Jido.Exec.Node.Input do
  @moduledoc false

  use Runic.Workflow.SingleOutput, batch_parent: false

  alias Jido.Exec.{Frame, Validation, ValueResolver}
  alias Runic.Identity
  alias Runic.Workflow.SingleOutput.{Context, Result}

  @enforce_keys [:id, :name, :hash, :component, :params]
  defstruct [:id, :name, :hash, :component, :params, :validator, :location, :node_path]

  @type t :: %__MODULE__{
          id: term(),
          name: atom() | String.t(),
          hash: Identity.t(),
          component: String.t(),
          params: term(),
          validator: module() | Jido.Flow.t() | nil
        }

  @doc false
  @spec new(keyword()) :: t()
  def new(opts) do
    opts =
      Keyword.validate!(opts, [
        :id,
        :name,
        :component,
        :params,
        :validator,
        :location,
        :node_path
      ])

    id = Keyword.fetch!(opts, :id)

    %__MODULE__{
      id: id,
      name: Keyword.fetch!(opts, :name),
      hash:
        Identity.digest(:component_definition, %{
          kind: "jido_flow_input",
          version: 1,
          id: inspect(id)
        }),
      component: Keyword.fetch!(opts, :component),
      params: Keyword.fetch!(opts, :params),
      validator: Keyword.get(opts, :validator),
      location: Keyword.get(opts, :location),
      node_path: Keyword.get(opts, :node_path, [Keyword.fetch!(opts, :component)])
    }
  end

  @doc false
  @spec resolve(t(), term(), map()) :: {:ok, Frame.nested_t()} | {:error, Exception.t()}
  def resolve(
        %__MODULE__{} = node,
        {:jido_invoke_flow_target, _target_id, input},
        context
      ),
      do: resolve(node, input, context)

  def resolve(%__MODULE__{} = node, input, context) do
    with {:ok, parent} <- Frame.merge(input),
         {:ok, params} <-
           ValueResolver.resolve(node.params, Frame.resolver_state(parent, context)),
         {:ok, params} <-
           Validation.input(node.validator, params, %{
             node_path: node.node_path,
             phase: :subflow_input
           }) do
      {:ok, Frame.nest(parent, params)}
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

defimpl Runic.Identity.Projectable, for: Jido.Exec.Node.Input do
  def identity_document(node) do
    %{kind: :jido_flow_input, version: 1, id: inspect(node.id)}
  end
end

defimpl Runic.Component, for: Jido.Exec.Node.Input do
  def connectable?(_node, _other), do: true

  def connect(node, to, workflow) do
    workflow
    |> Runic.Workflow.add_step(to, node)
    |> Runic.Workflow.draw_connection(node, node, :component_of, properties: %{kind: :flow_input})
    |> Runic.Workflow.register_component(node)
  end

  def source(node) do
    quote do
      Jido.Exec.Node.Input.new(
        id: unquote(Macro.escape(node.id)),
        name: unquote(node.name),
        component: unquote(node.component),
        params: unquote(Macro.escape(node.params)),
        validator: unquote(Macro.escape(node.validator)),
        location: unquote(Macro.escape(node.location)),
        node_path: unquote(Macro.escape(node.node_path))
      )
    end
  end

  def hash(node), do: node.hash
  def inputs(_node), do: [in: [type: :any]]
  def outputs(_node), do: [out: [type: :any]]
end

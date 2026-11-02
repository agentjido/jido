defmodule Jido.Exec.Node.Choice.Branch do
  @moduledoc false

  use Runic.Workflow.SingleOutput, batch_parent: false

  alias Jido.Exec.Frame
  alias Runic.Identity
  alias Runic.Workflow.SingleOutput.{Context, Result}

  @enforce_keys [:id, :name, :hash, :component, :option]
  defstruct [:id, :name, :hash, :component, :option, :location, :node_path]

  @type t :: %__MODULE__{}

  @doc false
  @spec new(keyword()) :: t()
  def new(opts) do
    opts =
      Keyword.validate!(opts, [
        :id,
        :name,
        :component,
        :option,
        :location,
        :node_path
      ])

    id = Keyword.fetch!(opts, :id)

    %__MODULE__{
      id: id,
      name: Keyword.fetch!(opts, :name),
      hash: Identity.digest(:component_definition, %{kind: "jido_choice_branch", version: 1, id: id}),
      component: Keyword.fetch!(opts, :component),
      option: Keyword.fetch!(opts, :option),
      location: Keyword.get(opts, :location),
      node_path: Keyword.get(opts, :node_path, [Keyword.fetch!(opts, :component)])
    }
  end

  @doc false
  @spec select(t(), term(), term()) :: {:ok, term()} | {:error, term()}
  def select(
        %__MODULE__{} = node,
        {:jido_choice_selection, option, input},
        _context
      ) do
    with {:ok, frame} <- Frame.merge(input) do
      {:ok, {:jido_choice_branch, node.option == option, frame}}
    end
  end

  @impl Runic.Workflow.SingleOutput
  @doc false
  @spec run(t(), term(), Context.t()) :: Result.t()
  def run(%__MODULE__{} = node, input, %Context{} = context) do
    case select(node, Jido.Exec.Fact.unwrap(input), context.runtime) do
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

defimpl Runic.Identity.Projectable, for: Jido.Exec.Node.Choice.Branch do
  def identity_document(node) do
    %{kind: :jido_choice_branch, version: 1, id: inspect(node.id)}
  end
end

defimpl Runic.Component, for: Jido.Exec.Node.Choice.Branch do
  def connectable?(_node, _other), do: true
  def connect(node, to, workflow), do: Runic.Workflow.add_step(workflow, to, node)

  def source(node) do
    quote do
      Jido.Exec.Node.Choice.Branch.new(
        id: unquote(Macro.escape(node.id)),
        name: unquote(node.name),
        component: unquote(node.component),
        option: unquote(node.option),
        location: unquote(Macro.escape(node.location)),
        node_path: unquote(Macro.escape(node.node_path))
      )
    end
  end

  def hash(node), do: node.hash
  def inputs(_node), do: [in: [type: :any]]
  def outputs(_node), do: [out: [type: :any]]
end

defmodule Jido.Exec.Node.Invoke.Completion do
  @moduledoc false

  use Runic.Workflow.SingleOutput, batch_parent: false

  alias Jido.Exec.Node.Invoke
  alias Runic.Identity
  alias Runic.Workflow.SingleOutput.{Context, Result}

  @enforce_keys [:id, :name, :hash]
  defstruct [:id, :name, :hash]

  @type t :: %__MODULE__{
          id: term(),
          name: String.t(),
          hash: Identity.t()
        }

  @doc false
  @spec new(Invoke.t()) :: t()
  def new(%Invoke{} = invoke) do
    id = {invoke.id, :completion}

    %__MODULE__{
      id: id,
      name: "__jido_invoke__/#{invoke.name}/completed",
      hash:
        Identity.digest(:component_definition, %{
          kind: "jido_invoke_completion",
          version: 1,
          id: inspect(id)
        })
    }
  end

  @impl Runic.Workflow.SingleOutput
  @doc false
  @spec run(t(), term(), Context.t()) :: Result.t()
  def run(%__MODULE__{}, input, %Context{} = context) do
    Jido.Exec.Fact.result(input, context, Jido.Exec.Fact.unwrap(input))
  end
end

defimpl Runic.Identity.Projectable, for: Jido.Exec.Node.Invoke.Completion do
  def identity_document(node),
    do: %{kind: :jido_invoke_completion, version: 1, id: inspect(node.id)}
end

defimpl Runic.Component, for: Jido.Exec.Node.Invoke.Completion do
  alias Jido.Exec.Node.Invoke.Completion
  alias Runic.Workflow

  def connectable?(_node, _other), do: true
  def connect(node, to, workflow), do: Workflow.add_step(workflow, to, node)

  def source(node) do
    quote do
      %Completion{
        id: unquote(Macro.escape(node.id)),
        name: unquote(node.name),
        hash: unquote(Macro.escape(node.hash))
      }
    end
  end

  def hash(node), do: node.hash
  def inputs(_node), do: [in: [type: :any]]
  def outputs(_node), do: [out: [type: :any]]
end

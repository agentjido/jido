defmodule Jido.Exec.Node.Loop.Start do
  @moduledoc false

  use Runic.Workflow.SingleOutput, batch_parent: false

  alias Runic.Identity
  alias Runic.Workflow.SingleOutput.{Context, Result}

  @enforce_keys [:id, :name, :hash, :loop]
  defstruct [:id, :name, :hash, :loop]

  @type t :: %__MODULE__{}

  @doc false
  @spec new(Jido.Exec.Node.Loop.t()) :: t()
  def new(%Jido.Exec.Node.Loop{} = loop) do
    id = {loop.id, :start}

    %__MODULE__{
      id: id,
      name: "__jido_#{loop.kind}__/#{loop.name}/start",
      hash:
        Identity.digest(:component_definition, %{
          kind: "jido_loop_start",
          version: 1,
          id: inspect(id)
        }),
      loop: loop
    }
  end

  @impl Runic.Workflow.SingleOutput
  @doc false
  @spec run(t(), term(), Context.t()) :: Result.t()
  def run(%__MODULE__{} = node, input, %Context{} = context) do
    case Jido.Exec.Node.Loop.start(node.loop, Jido.Exec.Fact.unwrap(input), context.runtime) do
      {:ok, value, loop} ->
        Jido.Exec.Fact.result(input, context, value, %{jido_loop: loop})

      {:error, error} ->
        Result.failure(
          Jido.Exec.Source.attach(error, node.loop.location, %{
            node: node.loop.component,
            node_path: node.loop.node_path
          })
        )
    end
  end
end

defimpl Runic.Identity.Projectable, for: Jido.Exec.Node.Loop.Start do
  def identity_document(node) do
    %{kind: :jido_loop_start, version: 1, id: inspect(node.id)}
  end
end

defimpl Runic.Component, for: Jido.Exec.Node.Loop.Start do
  def connectable?(_node, _other), do: true
  def connect(node, to, workflow), do: Runic.Workflow.add_step(workflow, to, node)

  def source(node) do
    quote do
      Jido.Exec.Node.Loop.Start.new(unquote(Macro.escape(node.loop)))
    end
  end

  def hash(node), do: node.hash
  def inputs(_node), do: [in: [type: :any]]
  def outputs(_node), do: [out: [type: :any]]
end

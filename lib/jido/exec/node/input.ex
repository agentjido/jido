defmodule Jido.Exec.Node.Input do
  @moduledoc false

  use Runic.Workflow.SingleOutput, batch_parent: false

  alias Jido.Exec.{Fact, Validation}
  alias Runic.Identity
  alias Runic.Workflow.SingleOutput.{Context, Result}

  @enforce_keys [:id, :name, :hash]
  defstruct [:id, :name, :hash, :validator, :location]

  @type t :: %__MODULE__{}

  @doc false
  @spec new(keyword()) :: t()
  def new(opts) do
    opts = Keyword.validate!(opts, [:id, :name, :validator, :location])

    id = Keyword.fetch!(opts, :id)

    %__MODULE__{
      id: id,
      name: Keyword.fetch!(opts, :name),
      hash:
        Identity.digest(:component_definition, %{
          kind: :jido_flow_input,
          version: 1,
          id: inspect(id)
        }),
      validator: Keyword.get(opts, :validator),
      location: Keyword.get(opts, :location)
    }
  end

  @impl Runic.Workflow.SingleOutput
  @doc false
  @spec run(t(), term(), Context.t()) :: Result.t()
  def run(%__MODULE__{} = node, input, %Context{} = context) do
    params = Fact.unwrap(input)

    case Validation.input(node.validator, params, %{phase: :flow_input}) do
      {:ok, value} ->
        Fact.result(input, context, value)

      {:error, error} ->
        Result.failure(Validation.attach_source(error, node.location, %{phase: :flow_input}))
    end
  end
end

defimpl Runic.Identity.Projectable, for: Jido.Exec.Node.Input do
  def identity_document(node), do: %{kind: :jido_flow_input, version: 1, id: inspect(node.id)}
end

defimpl Runic.Component, for: Jido.Exec.Node.Input do
  def connectable?(_node, _other), do: true

  def connect(node, parent, workflow) do
    workflow
    |> Runic.Workflow.add_step(parent, node)
    |> Runic.Workflow.draw_connection(node, node, :component_of, properties: %{kind: :flow_input})
    |> Runic.Workflow.register_component(node)
  end

  def source(node) do
    quote do
      Jido.Exec.Node.Input.new(
        id: unquote(Macro.escape(node.id)),
        name: unquote(node.name),
        validator: unquote(Macro.escape(node.validator)),
        location: unquote(Macro.escape(node.location))
      )
    end
  end

  def hash(node), do: node.hash
  def inputs(_node), do: [in: [type: :any]]
  def outputs(_node), do: [input: [type: :any]]
end

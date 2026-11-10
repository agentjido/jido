defmodule Jido.Exec.Node.Invoke.Finish do
  @moduledoc false

  use Runic.Workflow.SingleOutput, batch_parent: false

  alias Runic.Identity
  alias Runic.Workflow.ChildInvocation
  alias Runic.Workflow.SingleOutput.{Context, Result}

  @enforce_keys [:id, :name, :hash, :invoke_id, :invoke_name, :component, :target_component]
  defstruct [:id, :name, :hash, :invoke_id, :invoke_name, :component, :target_component]

  @type t :: %__MODULE__{}

  @doc false
  @spec new(map(), term()) :: t()
  def new(%{id: invoke_id, name: invoke_name, component: component} = invoke, target_id) do
    id = {invoke_id, :finish, target_id}

    %__MODULE__{
      id: id,
      name: "__jido_invoke__/#{invoke_name}/finish/#{target_id}",
      hash:
        Identity.digest(:component_definition, %{
          kind: "jido_invoke_finish",
          version: 1,
          id: inspect(id)
        }),
      invoke_id: invoke_id,
      invoke_name: invoke_name,
      component: component,
      target_component: target_component_key(invoke, target_id)
    }
  end

  @doc false
  @spec target_component_key(map(), term()) :: String.t()
  def target_component_key(%{component: component}, target_id),
    do: "__jido_invoke_target__/#{component}/#{target_id}"

  @doc false
  @spec condition(term(), term(), String.t()) :: Runic.Workflow.Condition.t()
  def condition(id, name, component) do
    source =
      quote do
        Jido.Exec.Node.Invoke.Finish.condition(
          unquote(Macro.escape(id)),
          unquote(name),
          unquote(component)
        )
      end

    %Runic.Workflow.Condition{
      name: "__jido_invoke__/#{name}/finished",
      hash:
        Identity.digest(:component_definition, %{
          kind: "jido_invoke_finished",
          version: 1,
          id: inspect(id)
        }),
      work: fn value -> complete?(value, component) end,
      arity: 1,
      closure: Runic.Closure.new(source, %{}, nil),
      meta_refs: []
    }
  end

  @doc false
  @spec complete?(term(), String.t()) :: boolean()
  def complete?(%ChildInvocation{}, _component), do: false

  def complete?(value, component) do
    case Jido.Exec.Frame.fetch_result(value, component) do
      {:ok, nil} -> false
      {:ok, _output} -> true
      :error -> false
    end
  end

  @doc false
  @spec finish(t(), term()) :: {:ok, term()} | {:error, term()}
  def finish(%__MODULE__{}, {:jido_invoke_target_result, frame, component, output, effects}) do
    {:ok, Jido.Exec.Frame.put_result(frame, component, output, effects)}
  end

  def finish(%__MODULE__{} = node, frame) do
    with {:ok, frame} <- Jido.Exec.Frame.merge(frame),
         {:ok, output} <- Jido.Exec.Frame.fetch_result(frame, node.target_component) do
      prior = Jido.Exec.Frame.effects_for(frame, node.component)
      target_effects = Jido.Exec.Frame.effects_for(frame, node.target_component)
      {:ok, Jido.Exec.Frame.put_result(frame, node.component, output, prior ++ target_effects)}
    end
  end

  @impl Runic.Workflow.SingleOutput
  @doc false
  @spec run(t(), term(), Context.t()) :: Result.t()
  def run(%__MODULE__{} = node, input, %Context{} = context) do
    case finish(node, Jido.Exec.Fact.unwrap(input)) do
      {:ok, value} -> Jido.Exec.Fact.result(input, context, value)
      {:error, error} -> Result.failure(error)
    end
  end
end

defimpl Runic.Identity.Projectable, for: Jido.Exec.Node.Invoke.Finish do
  def identity_document(node),
    do: %{kind: :jido_invoke_finish, version: 1, id: inspect(node.id)}
end

defimpl Runic.Component, for: Jido.Exec.Node.Invoke.Finish do
  def connectable?(_node, _other), do: true

  def connect(node, to, workflow) do
    workflow
    |> Runic.Workflow.add_step(to, node)
    |> Runic.Workflow.add_step(
      node,
      Jido.Exec.Node.Invoke.Finish.condition(
        node.invoke_id,
        node.invoke_name,
        node.component
      )
    )
  end

  def source(node) do
    quote do
      %Jido.Exec.Node.Invoke.Finish{
        id: unquote(Macro.escape(node.id)),
        name: unquote(node.name),
        hash: unquote(Macro.escape(node.hash)),
        invoke_id: unquote(Macro.escape(node.invoke_id)),
        invoke_name: unquote(node.invoke_name),
        component: unquote(node.component),
        target_component: unquote(node.target_component)
      }
    end
  end

  def hash(node), do: node.hash
  def inputs(_node), do: [in: [type: :any]]
  def outputs(_node), do: [out: [type: :any]]
end

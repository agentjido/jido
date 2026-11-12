defmodule Jido.Exec.Node.Output do
  @moduledoc false

  @behaviour Runic.Workflow.SingleOutput

  alias Jido.Exec.{Fact, Validation, ValueResolver}
  alias Runic.Identity
  alias Runic.Workflow.SingleOutput.{Context, Result}

  @enforce_keys [:id, :name, :hash, :output, :effect_order]
  defstruct [:id, :name, :hash, :output, :effect_order, :validator, :location]

  @type t :: %__MODULE__{}

  @doc false
  @spec __runic_single_output__() :: true
  def __runic_single_output__, do: true

  @doc false
  @spec __runic_batch_parent__() :: false
  def __runic_batch_parent__, do: false

  @doc false
  @spec new(keyword()) :: t()
  def new(opts) do
    opts = Keyword.validate!(opts, [:id, :name, :output, :effect_order, :validator, :location])
    id = Keyword.fetch!(opts, :id)

    %__MODULE__{
      id: id,
      name: Keyword.fetch!(opts, :name),
      hash:
        Identity.digest(:component_definition, %{
          kind: :jido_flow_output,
          version: 1,
          id: inspect(id)
        }),
      output: Keyword.fetch!(opts, :output),
      effect_order: Keyword.fetch!(opts, :effect_order),
      validator: Keyword.get(opts, :validator),
      location: Keyword.get(opts, :location)
    }
  end

  @impl Runic.Workflow.SingleOutput
  @doc false
  @spec run(t(), term(), Context.t()) :: Result.t()
  def run(%__MODULE__{} = node, input, %Context{} = context) do
    bindings = Fact.unwrap(input)

    handoff? =
      bindings
      |> Map.get(:controls, %{})
      |> Enum.any?(fn {_key, control} -> control == :handoff end)

    with {:ok, output} <-
           ValueResolver.resolve(
             node.output,
             ValueResolver.resolver_state(bindings, context.runtime)
           ),
         {:ok, output} <- validate_output(node, output, handoff?) do
      effects = ordered_effects(bindings, node.effect_order)
      metadata = %{jido: %{effects: effects} |> maybe_control(handoff?)}
      Fact.result(input, context, Fact.localize(output), metadata)
    else
      {:error, error} ->
        Result.failure(Validation.attach_source(error, node.location, %{phase: :flow_output}))
    end
  end

  defp validate_output(_node, %Jido.Instruction{} = instruction, true), do: {:ok, instruction}
  defp validate_output(node, output, _handoff?), do: Validation.output(node.validator, output)

  defp ordered_effects(bindings, order) do
    effects = Map.get(bindings, :effects, %{})
    Enum.flat_map(order, &Map.get(effects, &1, []))
  end

  defp maybe_control(metadata, true), do: Map.put(metadata, :control, :handoff)
  defp maybe_control(metadata, false), do: metadata
end

defimpl Runic.Identity.Projectable, for: Jido.Exec.Node.Output do
  def identity_document(node), do: %{kind: :jido_flow_output, version: 1, id: inspect(node.id)}
end

defimpl Runic.Workflow.Invokable, for: Jido.Exec.Node.Output do
  alias Runic.Workflow
  alias Runic.Workflow.{CausalContext, HookRunner, Runnable, SingleOutput}

  def match_or_execute(_node), do: :execute
  defdelegate prepare(node, workflow, fact), to: SingleOutput

  def invoke(node, workflow, fact) do
    {:ok, runnable} = prepare(node, workflow, fact)
    Workflow.apply_runnable(workflow, execute(node, runnable))
  end

  def execute(node, %Runnable{input_fact: fact, context: context} = runnable) do
    case HookRunner.run_before(context, node, fact) do
      {:ok, before_fns} ->
        after_context = CausalContext.with_hooks(context, {[], CausalContext.after_hooks(context)})
        executed = SingleOutput.execute(node, %{runnable | context: after_context})
        executed = %{executed | context: context}

        if executed.status == :completed,
          do: %{executed | hook_apply_fns: before_fns ++ executed.hook_apply_fns},
          else: executed

      {:error, reason} ->
        Runnable.fail(
          runnable,
          Jido.Exec.Validation.attach_source(reason, node.location, %{phase: :flow_output})
        )
    end
  end
end

defimpl Runic.Component, for: Jido.Exec.Node.Output do
  alias Jido.Exec.Node.Output
  alias Runic.Workflow

  def connectable?(_node, _other), do: true

  def connect(%Output{} = node, parents, workflow) when is_list(parents) do
    join = parents |> Enum.map(& &1.hash) |> Workflow.Join.new()
    workflow = Enum.reduce(parents, workflow, &Workflow.add_step(&2, &1, join))
    connect(node, join, workflow)
  end

  def connect(%Output{} = node, parent, workflow) do
    workflow
    |> Workflow.add_step(parent, node)
    |> Map.put(:output_ports, result: [type: :any, from: node.name])
    |> Workflow.draw_connection(node, node, :component_of, properties: %{kind: :flow_output})
    |> Workflow.register_component(node)
  end

  def source(%Output{} = node) do
    quote do
      Jido.Exec.Node.Output.new(
        id: unquote(Macro.escape(node.id)),
        name: unquote(node.name),
        output: unquote(Macro.escape(node.output)),
        effect_order: unquote(Macro.escape(node.effect_order)),
        validator: unquote(Macro.escape(node.validator)),
        location: unquote(Macro.escape(node.location))
      )
    end
  end

  def hash(%Output{hash: hash}), do: hash
  def inputs(_node), do: [bindings: [type: :any, doc: "Flow output bindings"]]
  def outputs(_node), do: [result: [type: :any, doc: "Flow output"]]
end

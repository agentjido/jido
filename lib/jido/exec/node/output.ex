defmodule Jido.Exec.Node.Output do
  @moduledoc false

  @behaviour Runic.Workflow.SingleOutput

  alias Jido.Exec.{Frame, Validation, ValueResolver}
  alias Runic.Identity
  alias Runic.Workflow.SingleOutput.{Context, Result}

  @enforce_keys [:id, :name, :hash, :output, :effect_order]
  defstruct [
    :id,
    :name,
    :hash,
    :output,
    :effect_order,
    :parent_component,
    :validator,
    :location
  ]

  @type t :: %__MODULE__{
          id: term(),
          name: atom() | String.t(),
          hash: Identity.t(),
          output: term(),
          effect_order: [String.t()],
          parent_component: String.t() | nil,
          validator: module() | Jido.Flow.t() | nil
        }

  @doc false
  @spec __runic_single_output__() :: true
  def __runic_single_output__, do: true

  @doc false
  @spec __runic_batch_parent__() :: false
  def __runic_batch_parent__, do: false

  @impl Runic.Workflow.SingleOutput
  @doc false
  @spec run(t(), term(), Context.t()) :: Result.t()
  def run(%__MODULE__{} = node, input, %Context{} = context) do
    handoff? = get_in(context.input_metadata, [:jido, :control]) == :handoff

    case resolve(node, Jido.Exec.Fact.unwrap(input), context.runtime, handoff?) do
      {:ok, value, effects} ->
        meta = if handoff?, do: %{effects: effects, control: :handoff}, else: %{effects: effects}
        Jido.Exec.Fact.result(input, context, value, %{jido: meta})

      {:error, error} ->
        phase = if is_nil(node.parent_component), do: :flow_output, else: :subflow_output
        Result.failure(Jido.Exec.Source.attach(error, node.location, %{phase: phase}))
    end
  end

  @doc false
  @spec new(keyword()) :: t()
  def new(opts) do
    opts =
      Keyword.validate!(opts, [
        :id,
        :name,
        :output,
        :effect_order,
        :parent_component,
        :validator,
        :location
      ])

    id = Keyword.fetch!(opts, :id)
    name = Keyword.fetch!(opts, :name)
    output = Keyword.fetch!(opts, :output)
    effect_order = Keyword.fetch!(opts, :effect_order)

    hash =
      Identity.digest(:component_definition, %{
        kind: "jido_flow_output",
        version: 1,
        id: inspect(id)
      })

    %__MODULE__{
      id: id,
      name: name,
      hash: hash,
      output: output,
      effect_order: effect_order,
      parent_component: Keyword.get(opts, :parent_component),
      validator: Keyword.get(opts, :validator),
      location: Keyword.get(opts, :location)
    }
  end

  defp resolve(node, input, context, handoff?) do
    with {:ok, frame} <- Frame.merge(input),
         {:ok, output} <- ValueResolver.resolve(node.output, Frame.resolver_state(frame, context)),
         {:ok, output} <- validate_output(node, output, handoff?) do
      effects = Frame.effects(frame, node.effect_order)
      complete_output(node, frame, output, effects)
    end
  end

  defp validate_output(%{parent_component: nil}, %Jido.Exec.Handoff{} = handoff, true),
    do: {:ok, handoff}

  defp validate_output(_node, %Jido.Exec.Handoff{}, true),
    do:
      {:error,
       Jido.Action.Error.config_error("handoff must finish the root Flow", %{
         reason: :nested_handoff
       })}

  defp validate_output(node, output, _handoff?), do: Validation.output(node.validator, output)

  defp complete_output(%__MODULE__{parent_component: nil}, _frame, output, effects),
    do: {:ok, output, effects}

  defp complete_output(
         %__MODULE__{parent_component: component},
         {:jido_nested_flow_frame, 1, _parent, _child} = frame,
         output,
         effects
       ) do
    {:ok, Frame.complete_nested(frame, component, output, effects), []}
  end

  defp complete_output(%__MODULE__{} = node, frame, _output, _effects) do
    {:error,
     Jido.Flow.Error.execution_error("nested Flow output has no parent frame", %{
       node: node.parent_component,
       reason: :invalid_nested_flow_frame,
       frame: frame
     })}
  end
end

defimpl Runic.Identity.Projectable, for: Jido.Exec.Node.Output do
  def identity_document(node) do
    %{kind: :jido_flow_output, version: 1, id: inspect(node.id)}
  end
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
        after_context =
          CausalContext.with_hooks(context, {[], CausalContext.after_hooks(context)})

        executed = SingleOutput.execute(node, %{runnable | context: after_context})
        executed = %{executed | context: context}

        if executed.status == :completed,
          do: %{executed | hook_apply_fns: before_fns ++ executed.hook_apply_fns},
          else: executed

      {:error, reason} ->
        phase = if is_nil(node.parent_component), do: :flow_output, else: :subflow_output
        Runnable.fail(runnable, Jido.Exec.Source.attach(reason, node.location, %{phase: phase}))
    end
  end
end

defimpl Runic.Component, for: Jido.Exec.Node.Output do
  alias Jido.Exec.Node.Output
  alias Runic.Workflow

  def connectable?(_node, _other), do: true

  def connect(%Output{} = node, to, workflow) when is_list(to) do
    join = to |> Enum.map(& &1.hash) |> Runic.Workflow.Join.new()
    workflow = Enum.reduce(to, workflow, &Workflow.add_step(&2, &1, join))

    workflow
    |> Workflow.add_step(join, node)
    |> register(node)
  end

  def connect(%Output{} = node, to, workflow) do
    workflow
    |> Workflow.add_step(to, node)
    |> register(node)
  end

  def source(%Output{} = node) do
    quote do
      Jido.Exec.Node.Output.new(
        id: unquote(Macro.escape(node.id)),
        name: unquote(node.name),
        output: unquote(Macro.escape(node.output)),
        effect_order: unquote(Macro.escape(node.effect_order)),
        parent_component: unquote(node.parent_component),
        validator: unquote(Macro.escape(node.validator)),
        location: unquote(Macro.escape(node.location))
      )
    end
  end

  def hash(%Output{hash: hash}), do: hash
  def inputs(_node), do: [in: [type: :any, doc: "Flow frame"]]
  def outputs(_node), do: [out: [type: :any, doc: "Flow output"]]

  defp register(workflow, %Output{parent_component: nil} = node) do
    workflow
    |> Map.put(:output_ports, result: [type: :any, from: node.name])
    |> register_output(node)
  end

  defp register(workflow, node), do: register_output(workflow, node)

  defp register_output(workflow, node) do
    workflow
    |> Workflow.draw_connection(node, node, :component_of, properties: %{kind: :flow_output})
    |> Workflow.register_component(node)
  end
end

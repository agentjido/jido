defmodule Jido.Exec.Compiler do
  @moduledoc false

  alias Jido.Error

  alias Jido.Exec.Node.{
    Action,
    Choice,
    Handoff,
    Input,
    Invoke,
    Iterate,
    Output,
    Parallel,
    Reduce,
    Subflow,
    Wait
  }

  alias Jido.Exec.Node.Map, as: MapNode
  alias Jido.Flow
  alias Jido.Flow.{Graph, Identity, Preparation, Value}
  alias Jido.Instruction
  alias Runic.Workflow

  @doc false
  @spec compile(term(), keyword()) :: {:ok, Workflow.t()} | {:error, Exception.t()}
  def compile(target, opts \\ []) do
    with {:ok, opts} <- validate_options(opts),
         {:ok, instruction} <- Instruction.resolve(target),
         :ok <- Instruction.validate_resolved(instruction),
         {:ok, instruction} <- Jido.Exec.Runtime.flow_instruction(instruction),
         {:ok, flow} <- Preparation.from_instruction(instruction),
         {:ok, flow, analysis, children} <- prepare_flow(flow),
         :ok <- reject_nested_waits(analysis, children) do
      {:ok,
       compile_flow(flow, analysis, children,
         source_map: source_map(opts, instruction.target),
         validator: instruction.target
       )}
    end
  rescue
    error -> {:error, error}
  end

  @doc false
  @spec compile!(term(), keyword()) :: Workflow.t() | no_return()
  def compile!(target, opts \\ []) do
    case compile(target, opts) do
      {:ok, workflow} -> workflow
      {:error, error} when is_exception(error) -> raise error
      {:error, reason} -> raise Error.config_error("Exec compilation failed", %{reason: reason})
    end
  end

  defp prepare_flow(flow) do
    with {:ok, attrs, analysis, children} <- Preparation.prepare(flow, [], %{}) do
      {:ok, struct!(Flow, attrs), analysis, children}
    end
  end

  defp reject_nested_waits(analysis, children) do
    Enum.reduce_while(analysis.ordered, :ok, fn
      {_name, %{kind: :call, call: %{kind: :flow, target: target}}}, :ok ->
        with {:ok, child_analysis} <- child_analysis(target, children),
             :ok <- reject_waits(child_analysis),
             :ok <- reject_nested_waits(child_analysis, children) do
          {:cont, :ok}
        else
          {:error, error} -> {:halt, {:error, error}}
        end

      _component, :ok ->
        {:cont, :ok}
    end)
  end

  defp child_analysis(target, children) when is_atom(target) do
    case Map.fetch(children, target) do
      {:ok, {_attrs, analysis}} -> {:ok, analysis}
      :error -> {:error, Error.config_error("prepared child Flow is missing", %{target: target})}
    end
  end

  defp child_analysis(%Flow{} = flow, children) do
    with {:ok, _attrs, analysis, _children} <- Preparation.prepare(flow, [], children),
         do: {:ok, analysis}
  end

  defp reject_waits(analysis) do
    case Enum.find(analysis.ordered, fn {_name, definition} -> definition.kind == :wait end) do
      nil ->
        :ok

      {name, _definition} ->
        {:error,
         Error.config_error("a nested Flow cannot suspend inside an authored component", %{
           node: name,
           reason: :nested_wait
         })}
    end
  end

  defp compile_flow(flow, analysis, children, opts) do
    digest = Identity.semantic_digest(flow, analysis.ordered)
    source_map = Keyword.fetch!(opts, :source_map)
    validator = Keyword.fetch!(opts, :validator)
    output_name = "__jido_output__/#{flow.name}/#{binary_part(digest, 0, 12)}"

    input =
      Input.new(
        id: {:flow_input, digest},
        name: "__jido_input__/#{flow.name}",
        validator: validator,
        location: Map.get(source_map, [:input])
      )

    workflow =
      Workflow.new(
        name: flow.name,
        output_ports: [result: [type: :any, from: output_name]]
      )
      |> Workflow.add(input)

    workflow =
      Enum.reduce(analysis.ordered, workflow, fn {name, definition}, current ->
        node =
          runtime_component(
            definition,
            [
              id: {:flow, digest, name},
              name: name,
              location: Map.get(source_map, [:components, name]),
              node_path: [name]
            ],
            name in analysis.terminals,
            children
          )

        Workflow.add(current, node,
          connections: component_connections(input.name, definition),
          input_mode: :all
        )
      end)

    output =
      Output.new(
        id: {:flow_output, digest},
        name: output_name,
        output: flow.output,
        effect_order: Enum.map(analysis.ordered, &elem(&1, 0)),
        validator: validator,
        location: Map.get(source_map, [:output])
      )

    connections =
      output_connections(
        input.name,
        Value.result_refs(flow.output),
        Enum.map(analysis.ordered, &elem(&1, 0)),
        analysis.terminals
      )

    Workflow.add(workflow, output, connections: connections, input_mode: :all)
  end

  defp runtime_component(%{kind: :wait, options: options}, opts, _terminal?, _children),
    do: Wait.new(opts ++ [options: options])

  defp runtime_component(
         %{kind: :call, call: %{kind: :action} = call},
         opts,
         _terminal?,
         _children
       ),
       do: Action.new(opts ++ [call: call])

  defp runtime_component(%{kind: :choice} = definition, opts, _terminal?, _children),
    do: Choice.new(opts ++ [definition: definition])

  defp runtime_component(%{kind: :parallel} = definition, opts, _terminal?, _children),
    do: Parallel.new(opts ++ [definition: definition])

  defp runtime_component(%{kind: :map} = definition, opts, _terminal?, _children),
    do: MapNode.new(opts ++ [definition: definition])

  defp runtime_component(%{kind: :reduce} = definition, opts, _terminal?, _children),
    do: Reduce.new(opts ++ [definition: definition])

  defp runtime_component(%{kind: :iterate} = definition, opts, _terminal?, _children),
    do: Iterate.new(opts ++ [definition: definition])

  defp runtime_component(%{kind: :invoke} = definition, opts, terminal?, _children),
    do: Invoke.new(opts ++ [definition: definition, terminal?: terminal?])

  defp runtime_component(%{kind: :handoff} = definition, opts, _terminal?, _children),
    do: Handoff.new(opts ++ [definition: definition])

  defp runtime_component(
         %{kind: :call, call: %{kind: :flow, target: target}} = definition,
         opts,
         _terminal?,
         children
       ) do
    Subflow.new(
      opts ++
        [
          definition: definition,
          child_workflow: compile_child!(target, children)
        ]
    )
  end

  defp runtime_component(definition, opts, _terminal?, _children) do
    raise Error.config_error("Flow component is not supported by Exec", %{
            component: Keyword.fetch!(opts, :name),
            kind: Map.get(definition, :kind),
            reason: :unsupported_component
          })
  end

  defp compile_child!(target, children) do
    {flow, analysis} = prepared_child!(target, children)

    compile_flow(flow, analysis, children,
      source_map: module_source_map(target),
      validator: target
    )
  end

  defp prepared_child!(target, children) when is_atom(target) do
    case Map.fetch(children, target) do
      {:ok, {attrs, analysis}} -> {struct!(Flow, attrs), analysis}
      :error -> raise Error.config_error("prepared child Flow is missing", %{target: target})
    end
  end

  defp prepared_child!(%Flow{} = flow, children) do
    case Preparation.prepare(flow, [], children) do
      {:ok, attrs, analysis, _children} -> {struct!(Flow, attrs), analysis}
      {:error, error} when is_exception(error) -> raise error
    end
  end

  defp component_connections(input, definition) do
    references = Graph.reference_dependencies(definition)
    needs = Graph.needs(definition) -- references

    [[from: {input, :input}, to: :bindings, target_path: [:input]]] ++
      Enum.map(references, fn dependency ->
        [
          from: {dependency, :value},
          to: :bindings,
          target_path: [:results, dependency]
        ]
      end) ++
      Enum.map(needs, fn dependency ->
        [
          from: {dependency, :control},
          to: :bindings,
          target_path: [:needs, dependency]
        ]
      end)
  end

  defp output_connections(input, result_sources, effect_sources, control_sources) do
    input_connection = [from: {input, :input}, to: :bindings, target_path: [:input]]

    result_connections =
      result_sources
      |> Enum.uniq()
      |> Enum.map(fn source ->
        [from: {source, :value}, to: :bindings, target_path: [:results, source]]
      end)

    effect_connections =
      Enum.map(effect_sources, fn source ->
        [from: {source, :effects}, to: :bindings, target_path: [:effects, source]]
      end)

    control_connections =
      Enum.map(control_sources, fn source ->
        [from: {source, :control}, to: :bindings, target_path: [:controls, source]]
      end)

    [input_connection | result_connections ++ effect_connections ++ control_connections]
  end

  defp validate_options(opts) when is_list(opts) do
    if Keyword.keyword?(opts) do
      case Keyword.keys(opts) -- [:source_map] do
        [] -> {:ok, opts}
        unknown -> {:error, Error.config_error("unknown compile options", %{options: unknown})}
      end
    else
      {:error, Error.config_error("compile options must be a keyword list")}
    end
  end

  defp validate_options(_opts),
    do: {:error, Error.config_error("compile options must be a keyword list")}

  defp source_map(opts, target),
    do: Keyword.get_lazy(opts, :source_map, fn -> module_source_map(target) end)

  defp module_source_map(module) when is_atom(module) do
    if function_exported?(module, :__jido_flow_source_map__, 0),
      do: module.__jido_flow_source_map__(),
      else: %{}
  end

  defp module_source_map(_target), do: %{}
end

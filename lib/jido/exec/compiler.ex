defmodule Jido.Exec.Compiler do
  @moduledoc false

  alias Jido.Error

  alias Jido.Exec.Node.{Action, Choice, Handoff, Input, Invoke, Loop, Output, Parallel}
  alias Jido.Exec.Node.Invoke.Completion
  alias Jido.Exec.Node.Map, as: MapComponent

  alias Jido.Flow
  alias Jido.Flow.{Identity, Validation}
  alias Jido.Instruction
  alias Runic.Workflow

  @doc false
  @spec compile(term(), keyword()) :: {:ok, Workflow.t()} | {:error, Exception.t()}
  def compile(target, opts \\ []) do
    with {:ok, opts} <- validate_options(opts),
         {:ok, instruction} <- normalize(target),
         :ok <- Instruction.validate_resolved(instruction),
         :ok <- validate_target_options(instruction, opts) do
      compile_instruction(instruction, opts)
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

  @doc false
  @spec compile_nested!(Instruction.t(), keyword()) :: Workflow.t() | no_return()
  def compile_nested!(%Instruction{kind: :flow} = instruction, opts) do
    with {:ok, flow} <- Validation.instruction_flow(instruction),
         {:ok, flow, analysis, children} <- Validation.prepare(flow, [], %{}),
         {:ok, workflow} <-
           compile_flow(
             flow,
             opts
             |> with_module_source_map(instruction.target)
             |> Keyword.put(:validation_target, instruction.target),
             analysis,
             children
           ) do
      workflow
    else
      {:error, error} when is_exception(error) ->
        raise error

      {:error, reason} ->
        raise Error.config_error("nested Flow compilation failed", %{reason: reason})
    end
  end

  @doc false
  @spec validate(Flow.t()) :: {:ok, Flow.t()} | {:error, Exception.t()}
  def validate(%Flow{} = flow) do
    with {:ok, flow, _analysis, _children} <- Validation.prepare(flow, [], %{}),
         do: {:ok, flow}
  end

  def validate(value), do: Flow.validate(value)

  defp compile_instruction(%Instruction{kind: :action} = instruction, opts) do
    name = Keyword.get(opts, :name)
    id = Keyword.get(opts, :id)
    node_opts = Enum.reject([name: name, id: id], fn {_key, value} -> is_nil(value) end)
    node = Action.new(instruction, node_opts)

    workflow =
      Workflow.new(
        name: "jido_action_#{node.name}",
        output_ports: [result: [type: :any, from: node.name]]
      )
      |> Workflow.add(node)

    {:ok, workflow}
  end

  defp compile_instruction(%Instruction{kind: :flow} = instruction, opts) do
    with {:ok, flow} <- Validation.instruction_flow(instruction),
         {:ok, flow, analysis, children} <- Validation.prepare(flow, [], %{}) do
      compile_flow(
        flow,
        opts
        |> with_module_source_map(instruction.target)
        |> Keyword.put(:validation_target, instruction.target),
        analysis,
        children
      )
    end
  end

  defp normalize(%Instruction{} = instruction), do: Instruction.resolve(instruction)
  defp normalize(%Flow{} = flow), do: Instruction.resolve(flow)

  defp normalize(module) when is_atom(module) and not is_nil(module),
    do: Instruction.resolve(module)

  defp normalize(target) do
    {:error, Error.config_error("unknown executable target", %{target: target, reason: :invalid_target})}
  end

  defp validate_options(opts) when is_list(opts) do
    if Keyword.keyword?(opts) do
      allowed = [:source_map, :name, :id]

      case Keyword.keys(opts) -- allowed do
        [] -> {:ok, opts}
        unknown -> {:error, Error.config_error("unknown compile options", %{options: unknown})}
      end
    else
      {:error, Error.config_error("compile options must be a keyword list")}
    end
  end

  defp validate_options(_opts),
    do: {:error, Error.config_error("compile options must be a keyword list")}

  # `name` and `id` name the root Action node, so a Flow target rejects them.
  defp validate_target_options(%Instruction{kind: :flow}, opts) do
    case Keyword.take(opts, [:name, :id]) do
      [] ->
        :ok

      [{option, _value} | _rest] ->
        {:error,
         Error.config_error("compile option applies only to an Action target", %{
           option: option
         })}
    end
  end

  defp validate_target_options(%Instruction{kind: :action}, opts) do
    case Keyword.fetch(opts, :name) do
      {:ok, name} when not (is_binary(name) or (is_atom(name) and not is_nil(name))) ->
        {:error,
         Error.config_error("compile option name must be a string or atom", %{
           option: :name,
           value: name
         })}

      _name ->
        :ok
    end
  end

  defp compile_flow(flow, opts, analysis, children) do
    digest = Identity.semantic_digest(flow, analysis.ordered)
    source_map = Keyword.get(opts, :source_map, %{})
    namespace = Keyword.get(opts, :namespace)
    boundary_name = Keyword.get(opts, :boundary_name)
    parent_component = Keyword.get(opts, :parent_component)
    input_params = Keyword.get(opts, :input_params)
    boundary_location = Keyword.get(opts, :boundary_location)
    validation_target = Keyword.get(opts, :validation_target)
    node_path_prefix = Keyword.get(opts, :node_path_prefix, [])
    ordered = analysis.ordered
    output = output_name(flow, digest, namespace)

    context = %{
      digest: digest,
      source_map: source_map,
      namespace: namespace,
      node_path_prefix: node_path_prefix,
      children: children
    }

    initial =
      Workflow.new(
        name: boundary_name || flow.name,
        input_ports: boundary_ports(boundary_name),
        output_ports: [result: [type: :any, from: output]]
      )

    {initial, root_parent} =
      add_flow_input(
        initial,
        namespace,
        boundary_name,
        parent_component,
        input_params,
        validation_target,
        boundary_location,
        node_path_prefix
      )

    with {:ok, workflow} <-
           add_flow_components(
             initial,
             analysis,
             context,
             root_parent
           ) do
      output =
        Output.new(
          id: {:flow_output, digest, namespace},
          name: output,
          output: flow.output,
          effect_order: Enum.map(ordered, &elem(&1, 0)),
          parent_component: parent_component,
          validator: validation_target,
          location: Map.get(source_map, [:output])
        )

      terminals =
        analysis.terminals
        |> Enum.map(&graph_name(namespace, &1))
        |> then(fn
          [] when not is_nil(root_parent) -> [root_parent]
          names -> names
        end)

      workflow = add_component(workflow, output, terminals)
      {:ok, workflow}
    end
  rescue
    error -> {:error, error}
  end

  defp add_flow_components(workflow, analysis, context, root_parent) do
    Enum.reduce_while(analysis.ordered, {:ok, workflow}, fn {name, node}, {:ok, current} ->
      opts = [
        id: {:flow, context.digest, context.namespace, name},
        name: graph_name(context.namespace, name),
        component: name,
        location: Map.get(context.source_map, [:components, name]),
        node_path: context.node_path_prefix ++ [name]
      ]

      case runtime_component(node, opts, context) do
        {:ok, component} ->
          dependencies =
            analysis.dependencies[name]
            |> Enum.map(&graph_name(context.namespace, &1))
            |> then(fn
              [] when not is_nil(root_parent) -> [root_parent]
              names -> names
            end)

          workflow = add_component(current, component, dependencies)

          {:cont, {:ok, workflow}}

        {:error, error} ->
          {:halt, {:error, error}}
      end
    end)
  end

  defp runtime_component(%{kind: :wait, options: options}, opts, _context),
    do: {:ok, Jido.Exec.Node.Wait.new(opts ++ [options: options])}

  defp runtime_component(
         %{kind: :call, call: %{kind: :action} = call},
         opts,
         context
       ) do
    flow = opts |> Keyword.take([:component, :location, :node_path]) |> Map.new()
    flow = Map.put(flow, :flow, context.digest)

    {:ok,
     Action.new(
       call,
       [flow: flow] ++ Keyword.take(opts, [:id, :name])
     )}
  end

  defp runtime_component(
         %{
           kind: :invoke,
           decision: %{kind: :action} = decision,
           expander: %{kind: :action} = expander
         },
         opts,
         _context
       ) do
    {:ok,
     Invoke.new(
       opts ++
         [
           decision: decision,
           expander: expander
         ]
     )}
  end

  defp runtime_component(
         %{kind: :handoff, selector: %{kind: :action} = selector},
         opts,
         _context
       ) do
    {:ok, Handoff.new(opts ++ [selector: selector])}
  end

  defp runtime_component(
         %{
           kind: :reduce,
           collection: collection,
           initial: initial,
           call: %{kind: :action} = call
         },
         opts,
         _context
       ) do
    {:ok,
     Loop.new(
       opts ++
         [
           kind: :reduce,
           collection: collection,
           initial: initial,
           call: call
         ]
     )}
  end

  defp runtime_component(
         %{
           kind: :iterate,
           call: %{kind: :action} = call,
           state: state,
           completion: completion,
           max_iterations: max_iterations
         },
         opts,
         _context
       ) do
    {:ok,
     Loop.new(
       opts ++
         [
           kind: :iterate,
           call: call,
           state: state,
           completion: completion,
           max_iterations: max_iterations
         ]
     )}
  end

  defp runtime_component(
         %{
           kind: :map,
           collection: collection,
           call: %{kind: :action} = call,
           on_error: on_error
         },
         opts,
         _context
       ) do
    {:ok,
     MapComponent.new(
       opts ++
         [
           collection: collection,
           call: call,
           on_error: on_error
         ]
     )}
  end

  defp runtime_component(
         %{kind: :parallel, actions: actions, on_error: on_error},
         opts,
         _context
       ) do
    {:ok, Parallel.new(opts ++ [actions: actions, on_error: on_error])}
  end

  defp runtime_component(
         %{kind: :choice, options: options, fallback: fallback},
         opts,
         _context
       ) do
    {:ok, Choice.new(opts ++ [options: options, fallback: fallback])}
  end

  defp runtime_component(
         %{kind: :call, call: %{kind: :flow, params: params} = instruction},
         opts,
         context
       ) do
    {flow, analysis} = Map.fetch!(context.children, instruction.target)
    name = Keyword.fetch!(opts, :component)
    child_namespace = nested_namespace(context.namespace, context.digest, name)
    child_source_map = module_source_map(instruction.target)

    compile_flow(
      flow,
      [
        source_map: child_source_map,
        namespace: child_namespace,
        boundary_name: Keyword.fetch!(opts, :name),
        parent_component: name,
        input_params: params,
        boundary_location: Keyword.get(opts, :location),
        validation_target: instruction.target,
        node_path_prefix: Keyword.fetch!(opts, :node_path)
      ],
      analysis,
      context.children
    )
  end

  defp runtime_component(
         node,
         opts,
         _context
       ) do
    {:error,
     Error.config_error("Flow component is not supported by this compiler gate", %{
       component: Keyword.fetch!(opts, :component),
       kind: node.kind,
       reason: :unsupported_component
     })}
  end

  defp add_component(workflow, component, []), do: Workflow.add(workflow, component)

  defp add_component(workflow, component, [parent]) do
    {parent, _source} = completed_parent(workflow, parent)
    Workflow.add(workflow, component, to: parent)
  end

  defp add_component(workflow, component, parents) do
    {target_port, _schema} = component |> Runic.Component.inputs() |> List.first()

    connections =
      parents
      |> Enum.with_index()
      |> Enum.map(fn {parent, index} ->
        {parent, source} = completed_parent(workflow, parent)

        {source_port, _schema} =
          source |> Runic.Component.outputs() |> List.first()

        [
          from: {parent, source_port},
          to: target_port,
          target_path: [index]
        ]
      end)

    Workflow.add(workflow, component, connections: connections, input_mode: :all)
  end

  defp completed_parent(workflow, parent) do
    case Workflow.get_component(workflow, parent) do
      %Invoke{} = source ->
        finished = Completion.new(source)
        {finished, finished}

      source ->
        {parent, source}
    end
  end

  defp add_flow_input(
         workflow,
         nil,
         nil,
         nil,
         nil,
         _validation_target,
         _location,
         _node_path_prefix
       ),
       do: {workflow, nil}

  defp add_flow_input(
         workflow,
         namespace,
         _boundary_name,
         parent_component,
         input_params,
         validation_target,
         location,
         node_path
       ) do
    input =
      Input.new(
        id: {:flow_input, namespace},
        name: graph_name(namespace, "__input__"),
        component: parent_component,
        params: input_params,
        validator: validation_target,
        location: location,
        node_path: node_path
      )

    {Workflow.add(workflow, input), input.name}
  end

  defp boundary_ports(nil), do: nil
  defp boundary_ports(_name), do: [in: [type: :any]]

  defp graph_name(nil, name), do: name
  defp graph_name(namespace, name), do: "#{namespace}/#{name}"

  defp nested_namespace(nil, digest, name),
    do: "__jido_nested__/#{binary_part(digest, 0, 12)}/#{name}"

  defp nested_namespace(namespace, digest, name),
    do: "#{namespace}/#{binary_part(digest, 0, 12)}/#{name}"

  defp output_name(flow, digest, namespace) do
    graph_name(namespace, "__jido_output__/#{flow.name}/#{binary_part(digest, 0, 12)}")
  end

  defp with_module_source_map(opts, target) do
    if Keyword.has_key?(opts, :source_map) do
      opts
    else
      Keyword.put(opts, :source_map, module_source_map(target))
    end
  end

  defp module_source_map(module) when is_atom(module) do
    if function_exported?(module, :__jido_flow_source_map__, 0) do
      module.__jido_flow_source_map__()
    else
      %{}
    end
  end

  defp module_source_map(_target), do: %{}
end

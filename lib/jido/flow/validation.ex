defmodule Jido.Flow.Validation do
  @moduledoc false

  alias Jido.Error
  alias Jido.Flow
  alias Jido.Flow.{Definition, Graph, Ref, Value}
  alias Jido.Instruction

  @doc false
  @spec validate_graph([Definition.named_component()], Value.t()) ::
          {:ok, Graph.analysis()} | {:error, [Definition.issue()]}
  def validate_graph(named_components, output) do
    {known, duplicates} = duplicate_name_issues(named_components)
    references = unknown_dependency_issues(named_components, output, known)

    case duplicates ++ references do
      [] ->
        analysis = Graph.analyze(Map.new(named_components))

        issues =
          case analysis do
            %{remaining: [], terminals: terminals} ->
              handoff_issues(named_components, output, terminals)

            %{remaining: names} ->
              [
                issue(
                  :cycle,
                  Error.validation_error("flow dependency graph contains a cycle", %{
                    components: names
                  }),
                  [:components]
                )
              ]
          end

        case output_issues(output) ++ issues do
          [] -> {:ok, analysis}
          issues -> {:error, issues}
        end

      issues ->
        {:error, output_issues(output) ++ issues}
    end
  end

  @doc false
  @spec validate_targets(Flow.t()) :: {:ok, Flow.t()} | {:error, Exception.t()}
  def validate_targets(%Flow{} = flow) do
    with {:ok, _children} <-
           validate_component_targets(Graph.canonical_components(flow.components), [], %{}) do
      {:ok, flow}
    end
  end

  @doc false
  @spec prepare(Flow.t(), list(), map()) ::
          {:ok, Flow.t(), map(), map()} | {:error, Exception.t()}
  def prepare(%Flow{} = flow, module_stack, children) do
    with {:ok, attrs, analysis} <- Definition.prepare_canonical(Map.from_struct(flow)),
         {:ok, children} <- validate_component_targets(analysis.ordered, module_stack, children) do
      {:ok, struct!(Flow, attrs), analysis, children}
    end
  end

  @doc false
  @spec instruction_flow(Instruction.t()) :: {:ok, Flow.t()} | {:error, Exception.t()}
  def instruction_flow(%Instruction{target: %Flow{} = flow}), do: {:ok, flow}

  def instruction_flow(%Instruction{target: module}) when is_atom(module) do
    try do
      case module.flow() do
        %Flow{} = flow ->
          {:ok, flow}

        value ->
          {:error, Error.config_error("Flow module returned invalid data", %{value: value})}
      end
    rescue
      error -> {:error, error}
    catch
      kind, reason ->
        {:error,
         Error.config_error("Flow module failed while returning its definition", %{
           module: module,
           kind: kind,
           reason: reason
         })}
    end
  end

  defp validate_component_targets(components, module_stack, children) do
    components
    |> Enum.reduce_while({:ok, children}, fn {name, component}, {:ok, children} ->
      case validate_component_target(name, component, module_stack, children) do
        {:ok, children} -> {:cont, {:ok, children}}
        {:error, error} -> {:halt, {:error, error}}
      end
    end)
  end

  defp validate_component_target(
         name,
         %{kind: :call, call: %{kind: :flow} = call},
         module_stack,
         children
       ) do
    with {:ok, instruction} <- resolve_target(call, :flow, name),
         :ok <- reject_recursive_flow(instruction.target, module_stack),
         {:ok, children} <- validate_child_flow(instruction.target, module_stack, children) do
      {:ok, children}
    else
      {:error, error} -> {:error, target_error(error, name, :flow)}
    end
  end

  defp validate_component_target(name, component, _module_stack, children) do
    component
    |> Definition.calls()
    |> Enum.reduce_while({:ok, children}, fn {role, call, _params}, {:ok, children} ->
      field = validation_field(component, role)

      case resolve_target(call, :action, name) do
        {:ok, _instruction} -> {:cont, {:ok, children}}
        {:error, error} -> {:halt, {:error, target_error(error, name, field)}}
      end
    end)
  end

  defp resolve_target(call, expected, component) do
    case Instruction.new(kind: call.kind, target: call.target) do
      {:ok, %Instruction{kind: ^expected} = instruction} ->
        case Instruction.validate_resolved(instruction) do
          :ok -> {:ok, instruction}
          {:error, error} -> {:error, error}
        end

      {:error, %{details: %{actual: actual}}}
      when actual in [:action, :flow] ->
        {:error,
         Error.validation_error("Flow component has the wrong target kind", %{
           component: component,
           expected: expected,
           actual: actual
         })}

      {:error, error} ->
        {:error, error}
    end
  end

  defp validate_child_flow(%Flow{} = child, module_stack, children) do
    with {:ok, _flow, _analysis, children} <-
           prepare(child, [child | module_stack], children),
         do: {:ok, children}
  end

  defp validate_child_flow(module, module_stack, children) when is_atom(module) do
    case Map.fetch(children, module) do
      {:ok, _child} ->
        {:ok, children}

      :error ->
        with {:ok, child} <- instruction_flow(%Instruction{target: module, kind: :flow}),
             {:ok, child, analysis, children} <-
               prepare(child, [module | module_stack], children) do
          {:ok, Map.put(children, module, {child, analysis})}
        end
    end
  end

  defp reject_recursive_flow(identity, module_stack) do
    if identity in module_stack do
      {:error,
       Error.validation_error("recursive nested Flow cycle", %{
         flow: identity,
         module_stack: Enum.reverse([identity | module_stack])
       })}
    else
      :ok
    end
  end

  defp target_error(error, component, field) do
    details =
      error
      |> Map.get(:details, %{})
      |> Map.merge(%{component: component, field: field, cause: error.__struct__})

    tagged = Error.validation_error(Exception.message(error), details)

    case Map.get(error, :stacktrace) do
      nil -> tagged
      stacktrace -> %{tagged | stacktrace: stacktrace}
    end
  end

  defp validation_field(%{kind: kind}, _role) when kind in [:call, :map, :reduce, :iterate],
    do: :action

  defp validation_field(_component, role), do: role

  defp output_issues(nil) do
    [
      issue(
        :output_required,
        Error.validation_error("Flow output is required", %{path: [:output]}),
        [:output]
      )
    ]
  end

  defp output_issues(_output), do: []

  defp duplicate_name_issues(named_components) do
    {known, issues} =
      named_components
      |> Enum.with_index()
      |> Enum.reduce({MapSet.new(), []}, fn {{name, _node}, index}, {known, issues} ->
        if MapSet.member?(known, name) do
          error = Error.validation_error("duplicate component name", %{name: name})
          {known, [issue(:duplicate_name, error, [:components, index, :name]) | issues]}
        else
          {MapSet.put(known, name), issues}
        end
      end)

    {known, Enum.reverse(issues)}
  end

  defp unknown_dependency_issues(named_components, output, known) do
    output_issues = unknown_refs(Value.result_refs(output), known, :output, [:output])

    component_issues =
      named_components
      |> Enum.with_index()
      |> Enum.flat_map(fn {{name, node}, index} ->
        unknown_refs(
          Definition.needs(node) ++ Definition.reference_dependencies(node),
          known,
          name,
          [
            :components,
            index
          ]
        )
      end)

    output_issues ++ component_issues
  end

  defp unknown_refs(names, known, owner, location) do
    names
    |> Enum.uniq()
    |> Enum.reject(&MapSet.member?(known, &1))
    |> Enum.map(fn name ->
      error =
        Error.validation_error("Flow reference points to an unknown component", %{
          owner: owner,
          component: name
        })

      issue(:unknown_dependency, error, location)
    end)
  end

  defp handoff_issues(named_components, output, terminals) do
    handoffs =
      named_components
      |> Enum.with_index()
      |> Enum.filter(fn {{_name, node}, _index} -> node.kind == :handoff end)

    errors =
      case handoffs do
        [] ->
          []

        [{{name, _node}, index}] ->
          handoff_sink_errors(terminals, name, index) ++
            handoff_output_errors(output, name)

        [_first, {{name, _node}, index} | _rest] ->
          [
            Error.validation_error("Flow can contain only one Handoff component", %{
              component: name,
              components: Enum.map(handoffs, fn {{handoff_name, _node}, _index} -> handoff_name end),
              path: [:components, index]
            })
          ]
      end

    Enum.map(errors, &issue(:handoff, &1, &1.details.path))
  end

  defp handoff_sink_errors(sinks, handoff_name, handoff_index) do
    if sinks == [handoff_name] do
      []
    else
      [
        Error.validation_error("Handoff must be the final component in the Flow", %{
          component: handoff_name,
          handoff: handoff_name,
          terminal_components: sinks,
          path: [:components, handoff_index]
        })
      ]
    end
  end

  defp handoff_output_errors(%Ref{source: :result, component: name, path: []}, name), do: []

  defp handoff_output_errors(_output, name) do
    [
      Error.validation_error("Flow output must be the complete Handoff result", %{
        handoff: name,
        path: [:output]
      })
    ]
  end

  defp issue(kind, error, location), do: %{kind: kind, error: error, location: location}
end

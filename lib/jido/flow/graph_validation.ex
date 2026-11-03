defmodule Jido.Flow.GraphValidation do
  @moduledoc false

  alias Jido.Error
  alias Jido.Flow.{Definition, Graph, Ref, Value}

  @doc false
  @spec validate([Definition.named_component()], Value.t()) ::
          {:ok, Graph.analysis()} | {:error, [Definition.issue()]}
  def validate(named_components, output) do
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

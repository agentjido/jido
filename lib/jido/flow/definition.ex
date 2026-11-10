defmodule Jido.Flow.Definition do
  @moduledoc false

  alias Jido.Instruction.Config
  alias Jido.Error
  alias Jido.Error.ValidationError
  alias Jido.Flow.{Component, Graph, Ref, Validation, Value}

  @keys [:name, :description, :schema, :output_schema, :components, :output]
  @type call :: Component.call()
  @type condition :: boolean() | Ref.t() | Jido.Expr.t()
  @type choice_option :: %{name: String.t(), condition: condition(), call: call()}
  @type component_node :: map()
  @type components :: %{optional(String.t()) => component_node()}
  @type named_component :: {String.t(), component_node()}
  @typedoc false
  @type issue :: %{kind: atom(), error: Exception.t(), location: list()}

  @doc false
  @spec validate(map()) :: {:ok, map()} | {:error, Exception.t()}
  def validate(attrs), do: first_error(diagnose(attrs))

  @doc false
  @spec validate_canonical(map()) :: {:ok, map()} | {:error, Exception.t()}
  def validate_canonical(attrs), do: first_error(without_analysis(diagnose(attrs, :canonical)))

  @doc false
  @spec prepare_canonical(map()) :: {:ok, map(), Graph.analysis()} | {:error, Exception.t()}
  def prepare_canonical(attrs), do: first_error(diagnose(attrs, :canonical))

  @doc false
  @spec diagnose(map()) :: {:ok, map()} | {:error, [issue()]}
  def diagnose(attrs), do: without_analysis(diagnose(attrs, :authoring))

  @doc false
  @spec diagnose_lowered(map()) :: {:ok, map()} | {:error, [issue()]}
  def diagnose_lowered(attrs), do: without_analysis(diagnose(attrs, :lowered))

  @doc false
  @spec diagnose_body(map(), term(), term()) :: {:ok, map()} | {:error, [issue()]}
  def diagnose_body(config, components, output) do
    attrs = %{components: components, output: output}
    without_analysis(diagnose_fields(attrs, body_fields(:lowered), :lowered, config, []))
  end

  defp diagnose(%{} = attrs, mode) when not is_struct(attrs) do
    unknown =
      case known_keys(attrs) do
        :ok -> []
        {:error, error} -> [error]
      end

    fields =
      [
        name: &Config.flow_name/1,
        description: &Config.description/1,
        schema: &Config.schema(&1, "schema"),
        output_schema: &Config.schema(&1, "output_schema")
      ] ++ body_fields(mode)

    diagnose_fields(attrs, fields, mode, %{}, unknown)
  end

  defp diagnose(_attrs, _mode),
    do: {:error, [issue(Error.validation_error("flow definition must be a map"))]}

  defp body_fields(mode) do
    [
      components: &components(&1, mode),
      output: &prepare_output(&1, mode)
    ]
  end

  defp diagnose_fields(attrs, fields, mode, initial, unknown) do
    {values, errors} =
      Enum.reduce(fields, {initial, unknown}, fn {field, validator}, {values, errors} ->
        result =
          case Map.get(attrs, field) do
            %ValidationError{details: %{flow_field_errors: errors}} -> {:error, errors}
            value -> validator.(value)
          end

        case result do
          {:ok, value} ->
            {Map.put(values, field, value), errors}

          {:error, nested} ->
            prefix = if field in [:components, :output], do: [], else: [field]
            {values, errors ++ Enum.map(List.wrap(nested), &Error.prefix_path(&1, prefix))}
        end
      end)

    if errors == [] do
      config = Map.take(values, [:name, :description, :schema, :output_schema])

      case canonical_config(attrs, config, mode) do
        :ok -> diagnose_normalized(Map.put(config, :output, values.output), values.components)
        {:error, error} -> {:error, [issue(error)]}
      end
    else
      errors =
        if Map.get(values, :output, :__unavailable__) == nil,
          do: errors ++ [Error.validation_error("Flow output is required", %{path: [:output]})],
          else: errors

      {:error, Enum.map(errors, &issue/1)}
    end
  end

  defp diagnose_normalized(attrs, components) do
    with {:ok, analysis} <- Validation.validate_graph(components, attrs.output) do
      {:ok, Map.put(attrs, :components, Map.new(components)), analysis}
    end
  end

  @doc false
  @spec component(term()) :: {:ok, named_component()} | {:error, Exception.t()}
  def component(attrs), do: component_result(Component.diagnose(attrs))

  @doc false
  @spec name(term()) :: {:ok, String.t()} | {:error, Exception.t()}
  def name(value) when is_atom(value) and not is_nil(value), do: name(Atom.to_string(value))

  def name(value) do
    case Config.validate_name(value) do
      :ok -> {:ok, value}
      {:error, message} -> {:error, Error.validation_error(message)}
    end
  end

  @doc false
  @spec invalid_subject(term()) :: {:error, Exception.t()}
  def invalid_subject(value),
    do: {:error, Error.validation_error("expected a Jido.Flow artifact", %{value: value})}

  @doc false
  @spec to_definition(components()) :: [map()]
  def to_definition(components),
    do: components |> Graph.canonical_components() |> Enum.map(&component_to_definition/1)

  @doc false
  @spec component_to_definition(named_component()) :: map()
  def component_to_definition({name, node}), do: Map.put(node, :name, name)

  @doc false
  @spec to_map(components()) :: [map()]
  def to_map(components), do: components |> to_definition() |> Enum.map(&Value.to_map/1)

  defp components(%{} = values, :canonical) when not is_struct(values) do
    values
    |> Enum.sort_by(fn {name, _} -> :erlang.term_to_binary(name) end)
    |> parse_components(:canonical)
  end

  defp components(values, mode) when is_list(values) and mode in [:authoring, :lowered] do
    if List.improper?(values),
      do: {:error, Error.validation_error("flow components must be a proper list", %{path: [:components]})},
      else: parse_components(values, mode)
  end

  defp components(_values, mode),
    do:
      {:error,
       Error.validation_error(
         if(mode == :canonical,
           do: "Flow components must be a canonical component map",
           else: "flow components must be a list"
         ),
         %{path: [:components]}
       )}

  defp parse_components([], _mode),
    do: {:error, Error.validation_error("Flow must declare at least one component", %{path: [:components]})}

  defp parse_components(values, mode) do
    {components, errors} =
      values
      |> Enum.with_index()
      |> Enum.reduce({[], []}, fn {value, index}, {components, errors} ->
        {result, location} = component_diagnostics(value, index, mode)

        case result do
          {:ok, component} ->
            {[component | components], errors}

          {:error, nested} ->
            {components,
             Enum.reduce(nested, errors, fn error, acc ->
               [Error.prefix_path(error, [:components, location]) | acc]
             end)}
        end
      end)

    if errors == [], do: {:ok, Enum.reverse(components)}, else: {:error, Enum.reverse(errors)}
  end

  defp component_diagnostics({name, %{name: _}}, _index, :canonical) do
    {{:error,
      [
        Error.validation_error("canonical component name belongs in the components key", %{
          path: [:name]
        })
      ]}, name}
  end

  defp component_diagnostics({name, node}, _index, :canonical)
       when is_map(node) and not is_struct(node),
       do: {Component.diagnose(Map.put(node, :name, name), :canonical), name}

  defp component_diagnostics({name, _node}, _index, :canonical),
    do: {Component.diagnose(nil, :canonical), name}

  defp component_diagnostics(attrs, index, mode),
    do: {Component.diagnose(attrs, mode), index}

  defp prepare_output(output, mode) when mode in [:authoring, :lowered] do
    case Value.prepare(output) do
      {:ok, output} -> {:ok, output}
      {:error, error} -> {:error, Error.prefix_path(error, [:output])}
    end
  end

  defp prepare_output(output, :canonical) do
    case Value.validate(output) do
      :ok -> {:ok, output}
      {:error, error} -> {:error, Error.prefix_path(error, [:output])}
    end
  end

  defp canonical_config(_attrs, _config, mode) when mode in [:authoring, :lowered], do: :ok

  defp canonical_config(attrs, config, :canonical) do
    case Enum.find(
           [:name, :description, :schema, :output_schema],
           &(Map.get(attrs, &1, :__missing__) != config[&1])
         ) do
      nil ->
        :ok

      field ->
        {:error,
         Error.validation_error("Flow artifact contains non-canonical data", %{
           path: [field],
           field: field,
           reason: :non_canonical
         })}
    end
  end

  defp known_keys(attrs) do
    case Map.keys(attrs) -- @keys do
      [] ->
        :ok

      keys ->
        key = Enum.min_by(keys, &:erlang.term_to_binary/1)

        {:error,
         Error.validation_error("unknown Flow configuration key: #{inspect(key)}", %{
           key: key,
           path: [key]
         })}
    end
  end

  defp component_result({:ok, value}), do: {:ok, value}
  defp component_result({:error, [error | _]}), do: {:error, error}
  defp first_error({:ok, value}), do: {:ok, value}
  defp first_error({:ok, value, analysis}), do: {:ok, value, analysis}

  defp first_error({:error, [issue | _]}),
    do: {:error, %{issue.error | details: Map.put(issue.error.details, :path, issue.location)}}

  defp issue(error),
    do: %{kind: :definition, error: error, location: Map.get(error.details, :path, [])}

  defp without_analysis({:ok, value, _analysis}), do: {:ok, value}
  defp without_analysis({:error, issues}), do: {:error, issues}
end

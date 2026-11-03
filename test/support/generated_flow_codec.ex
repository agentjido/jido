defmodule JidoActionTest.GeneratedFlowCodec do
  @moduledoc false

  alias Jido.Codec
  alias Jido.Codec.Registry
  alias Jido.Expr
  alias Jido.Flow
  alias Jido.Flow.Definition
  alias Jido.Flow.Ref

  @kinds [:action, :flow, :schema, :atom]
  @namespaces %{action: "actions", flow: "flows", schema: "schemas", atom: "atoms"}
  @tree_options [
    max_depth: 1_048_576,
    max_nodes: 1_048_576_000,
    max_binary_bytes: 1_048_576_000,
    max_integer_bits: 1_048_576
  ]

  def encode(%Flow{} = flow) do
    with {:ok, flow} <- Flow.validate(flow),
         {:ok, registry} <- flow |> entries() |> Registry.new(),
         {:ok, document} <- encode(flow, registry) do
      {:ok, document, registry}
    end
  end

  def encode(value),
    do: {:error, Jido.Flow.Error.validation_error("expected a Jido.Flow artifact", %{value: value})}

  def encode(value, registry),
    do: Jido.Flow.Codec.encode(value, registry)

  def decode(document, registry) do
    case Jido.Flow.Codec.diagnose(document, registry) do
      {:ok, flow} -> {:ok, flow}
      {:error, %Jido.Flow.Error.Invalid{errors: [error | _]}} -> {:error, error}
    end
  end

  def encode_json(value, registry),
    do: Codec.encode_json(value, registry: registry, codec: Jido.Flow.Codec)

  def decode_json(json, registry),
    do: Codec.decode_json(json, registry: registry, codec: Jido.Flow.Codec)

  defp entries(flow) do
    values =
      empty_values()
      |> add(:schema, flow.schema)
      |> add(:schema, flow.output_schema)
      |> collect_components(flow.components)
      |> collect_expression(flow.output)

    @kinds
    |> Enum.flat_map(fn kind ->
      values
      |> Map.fetch!(kind)
      |> MapSet.to_list()
      |> Enum.sort_by(&sort_key(kind, &1))
      |> Enum.with_index(1)
      |> Enum.map(fn {value, index} ->
        {{"#{Map.fetch!(@namespaces, kind)}/generated-#{index}", 1}, {kind, value}}
      end)
    end)
    |> Map.new()
  end

  defp empty_values, do: Map.new(@kinds, &{&1, MapSet.new()})
  defp add(values, kind, value), do: Map.update!(values, kind, &MapSet.put(&1, value))
  defp sort_key(kind, value) when kind in [:action, :flow, :atom], do: Atom.to_string(value)
  defp sort_key(:schema, value), do: :erlang.term_to_binary(value)

  defp collect_components(values, components) do
    Enum.reduce(components, values, fn {_name, node}, acc ->
      acc =
        Enum.reduce(Definition.calls(node), acc, fn {_role, instruction, _params}, inner ->
          add(inner, instruction.kind, instruction.target)
        end)

      acc = Enum.reduce(Definition.values(node), acc, &collect_expression(&2, &1))
      acc = collect_expression(acc, node.meta)

      case node do
        %{kind: :iterate, state: %{schema: schema}} -> add(acc, :schema, schema)
        _node -> acc
      end
    end)
  end

  defp collect_expression(values, expression) do
    reducer = fn
      %Ref{path: path}, _value_path, acc ->
        {:cont, collect_expression(acc, path)}

      value, _path, acc when is_map(value) and not is_struct(value) ->
        {:cont, Enum.reduce(Map.keys(value), acc, &collect_atom/2)}

      value, _path, acc when is_atom(value) and not is_nil(value) and not is_boolean(value) ->
        {:cont, collect_atom(value, acc)}

      _value, _path, acc ->
        {:cont, acc}
    end

    {:ok, values} = Expr.reduce(expression, values, reducer, @tree_options)
    values
  end

  defp collect_atom(value, values)
       when is_atom(value) and not is_nil(value) and not is_boolean(value),
       do: add(values, :atom, value)

  defp collect_atom(_value, values), do: values
end

defmodule JidoActionTest.FlowCodec do
  @moduledoc false

  defdelegate encode(flow), to: JidoActionTest.GeneratedFlowCodec
  defdelegate encode(flow, registry), to: JidoActionTest.GeneratedFlowCodec
  defdelegate decode(document, registry), to: JidoActionTest.GeneratedFlowCodec
  defdelegate encode_json(flow, registry), to: JidoActionTest.GeneratedFlowCodec
  defdelegate decode_json(json, registry), to: JidoActionTest.GeneratedFlowCodec
  defdelegate diagnose(document, registry), to: Jido.Flow.Codec
end

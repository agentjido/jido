defmodule Jido.Exec.Node.Lifecycle do
  @moduledoc false

  alias Jido.Exec.{Fact, Runtime, Validation}
  alias Runic.Workflow.SingleOutput.{Context, Result}

  @type execution_result ::
          {:ok, term(), [term()]}
          | {:ok, term(), [term()], :none | :handoff}
          | {:error, Exception.t()}

  @doc false
  @spec run(struct(), term(), Context.t(), (map() -> execution_result())) :: Result.t()
  def run(node, input, %Context{} = context, work) when is_function(work, 1) do
    result =
      Runtime.with_application_logging(fn ->
        Runtime.with_execution_context(context.runtime, fn ->
          work.(Fact.unwrap(input))
        end)
      end)

    publish(result, node, input, context)
  end

  defp publish({:ok, value, effects}, node, input, context),
    do: publish({:ok, value, effects, :none}, node, input, context)

  defp publish({:ok, value, effects, control}, _node, input, context) do
    metadata = if control == :handoff, do: %{jido: %{control: :handoff}}, else: %{}
    output = Fact.localize(%{value: value, effects: effects, control: control})
    Fact.result(input, context, output, metadata)
  end

  defp publish({:error, error}, node, _input, _context),
    do: Result.failure(attach_source(error, node))

  defp attach_source(error, node) do
    details = Map.get(error, :details, %{})

    path =
      case Map.get(details, :node_path) do
        nil ->
          node.node_path

        path when is_list(path) ->
          if Enum.take(path, length(node.node_path)) == node.node_path,
            do: path,
            else: node.node_path ++ path
      end

    extra =
      %{}
      |> maybe_put(:node, if(Map.has_key?(details, :node), do: nil, else: node.name))
      |> Map.put(:node_path, path)

    location = if Map.has_key?(details, :source), do: nil, else: node.location
    Validation.attach_source(error, location, extra)
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)
end

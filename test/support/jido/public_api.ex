defmodule Jido.Test.PublicAPI do
  @moduledoc false

  def documented_api(module) do
    module
    |> entries()
    |> Enum.flat_map(fn
      {{kind, name, arity}, _, _, doc, _}
      when kind in [:function, :macro] and doc not in [:hidden, :none] ->
        [{kind, name, arity}]

      _other ->
        []
    end)
    |> Enum.sort()
  end

  def documented_functions(module) do
    module
    |> entries()
    |> Enum.flat_map(fn
      {{:function, name, arity}, _, _, doc, _} when doc not in [:hidden, :none] ->
        [{name, arity}]

      _other ->
        []
    end)
    |> Enum.sort()
  end

  def documented_types(module) do
    module
    |> entries()
    |> Enum.flat_map(fn
      {{:type, name, arity}, _, _, doc, _} when doc not in [:hidden, :none] ->
        [{:type, name, arity}]

      _other ->
        []
    end)
    |> Enum.sort()
  end

  def public_module?(module) do
    {:docs_v1, _, _, _, module_doc, _, _} = Code.fetch_docs(module)
    module_doc not in [:hidden, :none]
  end

  defp entries(module) do
    {:docs_v1, _, _, _, _, _, entries} = Code.fetch_docs(module)
    entries
  end
end

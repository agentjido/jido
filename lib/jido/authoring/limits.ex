defmodule Jido.Authoring.Limits do
  @moduledoc false

  @doc false
  defmacro maximum_depth, do: 100

  @doc false
  defmacro maximum_collection_size, do: 10_000

  @doc false
  defmacro maximum_document_nodes, do: 100_000
end

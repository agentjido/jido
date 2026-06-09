defmodule Jido.Util.DeepMerge do
  @moduledoc false

  @doc false
  @spec merge(term(), term()) :: term()
  def merge(left, right) when is_map(left) and is_map(right) do
    if is_struct(left) or is_struct(right) do
      right
    else
      Map.merge(left, right, &merge_value/3)
    end
  end

  def merge(left, right) when is_list(left) and is_list(right) do
    cond do
      keyword_list?(left) and right == [] ->
        left

      keyword_list?(left) and keyword_list?(right) ->
        Keyword.merge(left, right, &merge_value/3)

      true ->
        right
    end
  end

  def merge(_left, right), do: right

  defp merge_value(_key, left, right), do: merge(left, right)

  defp keyword_list?(list), do: Keyword.keyword?(list)
end

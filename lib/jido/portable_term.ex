defmodule Jido.PortableTerm do
  @moduledoc false

  @spec valid?(term()) :: boolean()
  def valid?(term)
      when is_pid(term) or is_reference(term) or is_port(term) or is_function(term),
      do: false

  def valid?(term) when is_map(term) do
    term
    |> Map.to_list()
    |> Enum.all?(fn {key, value} -> valid?(key) and valid?(value) end)
  end

  def valid?(term) when is_tuple(term),
    do: term |> Tuple.to_list() |> Enum.all?(&valid?/1)

  def valid?([]), do: true
  def valid?([head | tail]), do: valid?(head) and valid_list_tail?(tail)
  def valid?(_term), do: true

  defp valid_list_tail?([]), do: true
  defp valid_list_tail?([head | tail]), do: valid?(head) and valid_list_tail?(tail)
  defp valid_list_tail?(_improper_tail), do: false
end

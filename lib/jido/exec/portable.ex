defmodule Jido.Exec.Portable do
  @moduledoc false

  alias Jido.Action.Error

  @typep local_type :: :pid | :port | :reference | :function

  @doc false
  @spec validate(term(), atom()) :: :ok | {:error, Exception.t()}
  def validate(value, field) do
    case validate_local(value, [field]) do
      :ok ->
        :ok

      {:error, type, path} ->
        {:error,
         Error.execution_error("durable execution data contains a process-local value", %{
           phase: :durability,
           reason: :non_portable_durable_value,
           type: type,
           path: path,
           retry: false
         })}
    end
  end

  @spec validate_local(term(), [term()]) :: :ok | {:error, local_type(), [term()]}
  defp validate_local(term, path)
       when is_pid(term) or is_reference(term) or is_port(term) or is_function(term),
       do: {:error, local_type(term), path}

  defp validate_local(term, path) when is_map(term) do
    term
    |> Map.to_list()
    |> Enum.reduce_while(:ok, fn {key, value}, :ok ->
      with :ok <- validate_local(key, path ++ [:key]),
           :ok <- validate_local(value, path ++ [key]) do
        {:cont, :ok}
      else
        {:error, _type, _path} = error -> {:halt, error}
      end
    end)
  end

  defp validate_local(term, path) when is_tuple(term) do
    term
    |> Tuple.to_list()
    |> Enum.with_index()
    |> Enum.reduce_while(:ok, fn {value, index}, :ok ->
      case validate_local(value, path ++ [index]) do
        :ok -> {:cont, :ok}
        {:error, _type, _path} = error -> {:halt, error}
      end
    end)
  end

  defp validate_local([], _path), do: :ok
  defp validate_local([_head | _tail] = term, path), do: validate_list(term, path, 0)
  defp validate_local(_term, _path), do: :ok

  defp validate_list([], _path, _index), do: :ok

  defp validate_list([value | rest], path, index) do
    case validate_local(value, path ++ [index]) do
      :ok when is_list(rest) -> validate_list(rest, path, index + 1)
      :ok -> validate_local(rest, path ++ [:tail])
      {:error, _type, _path} = error -> error
    end
  end

  defp local_type(term) when is_pid(term), do: :pid
  defp local_type(term) when is_port(term), do: :port
  defp local_type(term) when is_reference(term), do: :reference
  defp local_type(term) when is_function(term), do: :function
end

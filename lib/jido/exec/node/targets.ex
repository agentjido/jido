defmodule Jido.Exec.Node.Targets do
  @moduledoc false

  @doc false
  @spec versions(map()) :: map()
  def versions(definition) do
    definition
    |> Jido.Flow.Component.calls()
    |> Enum.reduce(%{}, fn {_role, call, _params}, versions ->
      if is_atom(call.target),
        do: Map.put(versions, {call.kind, call.target}, version(call.target)),
        else: versions
    end)
  end

  @doc false
  @spec compatible(map()) :: :ok | {:error, Exception.t()}
  def compatible(versions) when is_map(versions) do
    Enum.reduce_while(versions, :ok, fn {{kind, target}, expected}, :ok ->
      case compatible(kind, target, expected) do
        :ok -> {:cont, :ok}
        {:error, error} -> {:halt, {:error, error}}
      end
    end)
  end

  @doc false
  @spec compatible(:action | :flow, module(), term()) :: :ok | {:error, Exception.t()}
  def compatible(kind, target, expected) do
    actual = version(target)

    if actual == expected do
      :ok
    else
      {:error,
       Jido.Error.config_error("#{target_label(kind)} target code changed after the graph was built", %{
         target: target,
         expected: expected,
         actual: actual,
         reason: :incompatible_target
       })}
    end
  end

  @doc false
  @spec version(module()) :: term()
  def version(target), do: target.module_info(:md5)

  defp target_label(:action), do: "Action"
  defp target_label(:flow), do: "Flow"
end

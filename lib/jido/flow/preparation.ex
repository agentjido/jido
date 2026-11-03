defmodule Jido.Flow.Preparation do
  @moduledoc false

  alias Jido.Error
  alias Jido.Flow.{Definition, Graph, Validation}
  alias Jido.Instruction

  @flow_module Module.concat(["Jido", "Flow"])

  @doc false
  @spec prepare(map(), list(), map()) ::
          {:ok, map(), Graph.analysis(), map()} | {:error, Exception.t()}
  def prepare(flow, module_stack, children) when is_map(flow) do
    with {:ok, attrs, analysis} <- Definition.prepare_canonical(flow_attrs(flow)),
         {:ok, children} <-
           Validation.validate_component_targets(
             analysis.ordered,
             module_stack,
             children,
             &prepare_child/3
           ) do
      {:ok, attrs, analysis, children}
    end
  end

  @doc false
  @spec from_instruction(Instruction.t()) :: {:ok, map()} | {:error, Exception.t()}
  def from_instruction(%Instruction{target: target}) when is_map(target) do
    if flow?(target),
      do: {:ok, target},
      else: {:error, Error.config_error("Flow instruction contains invalid data", %{value: target})}
  end

  def from_instruction(%Instruction{target: module}) when is_atom(module) do
    try do
      case module.flow() do
        flow when is_map(flow) ->
          if flow?(flow),
            do: {:ok, flow},
            else: {:error, Error.config_error("Flow module returned invalid data", %{value: flow})}

        value ->
          {:error, Error.config_error("Flow module returned invalid data", %{value: value})}
      end
    rescue
      error -> {:error, error}
    catch
      kind, reason ->
        {:error,
         Error.config_error("Flow module failed while returning its definition", %{
           module: module,
           kind: kind,
           reason: reason
         })}
    end
  end

  defp prepare_child(child, module_stack, children) when is_map(child) do
    if flow?(child) do
      with {:ok, _attrs, _analysis, children} <-
             prepare(child, [child | module_stack], children),
           do: {:ok, children}
    else
      {:error, Error.config_error("nested Flow target contains invalid data", %{value: child})}
    end
  end

  defp prepare_child(module, module_stack, children) when is_atom(module) do
    case Map.fetch(children, module) do
      {:ok, _child} ->
        {:ok, children}

      :error ->
        with {:ok, child} <- from_instruction(%Instruction{target: module, kind: :flow}),
             {:ok, attrs, analysis, children} <-
               prepare(child, [module | module_stack], children) do
          {:ok, Map.put(children, module, {attrs, analysis})}
        end
    end
  end

  defp flow?(value), do: Map.get(value, :__struct__) == @flow_module

  defp flow_attrs(%{__struct__: module} = flow) when module == @flow_module,
    do: Map.from_struct(flow)

  defp flow_attrs(attrs), do: attrs
end

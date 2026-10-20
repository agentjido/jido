defmodule Jido.Agent.Codec.Registry do
  @moduledoc false

  alias Jido.Agent.{Authoring, Data, Extension}
  alias Jido.Authoring.Registry

  @kinds [:agent, :action, :flow, :plugin, :extension, :transform, :schema, :atom]

  @spec new(map() | Registry.t()) :: {:ok, Registry.t()} | {:error, Exception.t()}
  def new(entries) do
    with {:ok, registry} <- Registry.new(entries),
         :ok <- validate_entries(registry.entries) do
      {:ok, registry}
    end
  end

  defp validate_entries(entries) do
    Authoring.check_each(entries, fn
      {_identifier, {:alias, _write_identifier}} ->
        :ok

      {_identifier, {kind, value}} when kind in @kinds ->
        validate_value(kind, value)

      {_identifier, {kind, _value}} ->
        Authoring.error("Invalid Agent Registry kind", %{kind: kind})

      {_identifier, _entry} ->
        Authoring.error("Invalid Agent Registry entry")
    end)
  end

  defp validate_value(:atom, value) when is_atom(value), do: :ok
  defp validate_value(:schema, value), do: Data.schema(value)

  defp validate_value(:agent, value) when is_atom(value) do
    if value == Jido.Agent or Jido.Agent.Validation.loaded_agent_module?(value),
      do: :ok,
      else: Authoring.error("Invalid Agent Registry module", %{kind: :agent})
  end

  defp validate_value(:extension, value) when is_atom(value) do
    with {:ok, _provider} <- Extension.provider(value), do: :ok
  end

  defp validate_value(:plugin, value) when is_atom(value) do
    if Code.ensure_loaded?(value) and function_exported?(value, :__jido_plugin__, 0),
      do: :ok,
      else: Authoring.error("Invalid Agent Registry module", %{kind: :plugin})
  end

  defp validate_value(:transform, {module, function, 1})
       when is_atom(module) and is_atom(function) do
    if Code.ensure_loaded?(module) and function_exported?(module, function, 1),
      do: :ok,
      else: Authoring.error("Invalid Agent transform reference")
  end

  defp validate_value(kind, value) when kind in [:action, :flow] do
    with {:ok, %{kind: ^kind}} <- Jido.Instruction.resolve(value),
         :ok <- Jido.Instruction.validate(value) do
      :ok
    else
      _ -> Authoring.error("Invalid Agent Registry executable", %{kind: kind})
    end
  end

  defp validate_value(kind, _value),
    do: Authoring.error("Invalid Agent Registry value", %{kind: kind})
end

defmodule Jido.Plugin.Manifest do
  @moduledoc """
  Static owner-facet metadata for one Plugin package.

  A manifest contains module identities, a positive package version, and an
  optional mapping from common declaration options to each facet. It contains
  no callback, process, Turn, persistence record, or Topology plan data.
  """

  alias Jido.Error

  @owners [:agent, :agent_server, :persistence, :topology]

  @enforce_keys [:module]
  defstruct module: nil,
            vsn: 1,
            agent: nil,
            agent_server: nil,
            persistence: nil,
            topology: nil,
            option_keys: %{}

  @type owner :: :agent | :agent_server | :persistence | :topology
  @type t :: %__MODULE__{
          module: module(),
          vsn: pos_integer(),
          agent: module() | nil,
          agent_server: module() | nil,
          persistence: module() | nil,
          topology: module() | nil,
          option_keys: %{optional(owner()) => [atom()]}
        }

  @doc "Returns the closed list of Plugin facet owners."
  @spec owners() :: [owner()]
  def owners, do: @owners

  @doc "Returns the facet module for one owner."
  @spec facet(t(), owner()) :: module() | nil
  def facet(%__MODULE__{} = manifest, owner) when owner in @owners,
    do: Map.fetch!(manifest, owner)

  @doc "Returns the declaration options assigned to one facet."
  @spec options_for(t(), owner(), keyword()) :: keyword()
  def options_for(%__MODULE__{option_keys: option_keys}, owner, options)
      when owner in @owners and is_list(options) do
    case {map_size(option_keys), Map.fetch(option_keys, owner)} do
      {0, _result} -> options
      {_size, {:ok, keys}} -> Keyword.take(options, keys)
      {_size, :error} -> []
    end
  end

  @doc "Validates static manifest metadata and common declaration options."
  @spec validate(t(), keyword()) :: {:ok, t()} | {:error, Error.ValidationError.t()}
  def validate(%__MODULE__{} = manifest, options) when is_list(options) do
    with :ok <- validate_module(manifest.module),
         :ok <- validate_vsn(manifest.vsn),
         :ok <- validate_facets(manifest),
         :ok <- validate_option_keys(manifest, options),
         :ok <- validate_static_options(options) do
      {:ok, manifest}
    end
  end

  def validate(manifest, options),
    do:
      invalid("Plugin manifest or declaration options are invalid", %{
        manifest: manifest,
        options: options
      })

  defp validate_module(module) when is_atom(module) and not is_nil(module), do: :ok
  defp validate_module(module), do: invalid("Plugin package module is invalid", %{module: module})

  defp validate_vsn(vsn) when is_integer(vsn) and vsn > 0, do: :ok
  defp validate_vsn(vsn), do: invalid("Plugin package version must be positive", %{vsn: vsn})

  defp validate_facets(manifest) do
    facets = Enum.map(@owners, &Map.fetch!(manifest, &1))

    cond do
      Enum.all?(facets, &is_nil/1) ->
        invalid("Plugin manifest must select at least one facet", %{plugin: manifest.module})

      invalid = Enum.find(facets, &(not is_nil(&1) and not is_atom(&1))) ->
        invalid("Plugin facet module is invalid", %{plugin: manifest.module, facet: invalid})

      true ->
        :ok
    end
  end

  defp validate_option_keys(%__MODULE__{option_keys: option_keys} = manifest, options)
       when is_map(option_keys) do
    invalid_owner =
      Enum.find_value(Map.keys(option_keys), fn owner ->
        if owner not in @owners, do: {:invalid, owner}
      end)

    invalid_keys =
      Enum.find_value(option_keys, fn {owner, keys} ->
        if is_list(keys) and Enum.all?(keys, &is_atom/1) and Enum.uniq(keys) == keys,
          do: nil,
          else: {owner, keys}
      end)

    unselected_owner =
      Enum.find_value(Map.keys(option_keys), fn owner ->
        if owner in @owners and is_nil(Map.fetch!(manifest, owner)), do: {:unselected, owner}
      end)

    assigned = option_keys |> Map.values() |> List.flatten() |> MapSet.new()
    unassigned = options |> Keyword.keys() |> Enum.reject(&MapSet.member?(assigned, &1))

    cond do
      invalid_owner ->
        invalid("Plugin option mapping has an unknown owner", %{
          owner: elem(invalid_owner, 1),
          owners: @owners
        })

      invalid_keys ->
        invalid("Plugin option mapping must contain unique atom keys", %{
          mapping: invalid_keys
        })

      unselected_owner ->
        invalid("Plugin option mapping names an unselected facet", %{
          owner: elem(unselected_owner, 1)
        })

      map_size(option_keys) > 0 and unassigned != [] ->
        invalid("Plugin declaration contains unassigned options", %{options: unassigned})

      true ->
        :ok
    end
  end

  defp validate_option_keys(%__MODULE__{option_keys: option_keys}, _options),
    do: invalid("Plugin option mapping must be a map", %{option_keys: option_keys})

  defp validate_static_options(options) do
    case Jido.Action.validate_static_data(options) do
      :ok ->
        :ok

      {:error, reason} ->
        invalid("Plugin declaration options must be static data", %{reason: reason})
    end
  end

  defp invalid(message, details) do
    {:error, Error.validation_error(message, kind: :config, details: details)}
  end
end

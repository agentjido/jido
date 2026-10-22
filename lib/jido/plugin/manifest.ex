defmodule Jido.Plugin.Manifest do
  @moduledoc false

  alias Jido.Error

  @owners [:agent, :agent_server, :persistence]

  @enforce_keys [:module]
  defstruct module: nil,
            vsn: 1,
            agent: nil,
            agent_server: nil,
            persistence: nil,
            option_keys: %{}

  @type owner :: :agent | :agent_server | :persistence
  @type t :: %__MODULE__{
          module: module(),
          vsn: pos_integer(),
          agent: module() | nil,
          agent_server: module() | nil,
          persistence: module() | nil,
          option_keys: %{optional(owner()) => [atom()]}
        }

  @doc "Returns the closed list of Plugin callback owners."
  @spec owners() :: [owner()]
  def owners, do: @owners

  @doc "Returns the Plugin module when it has callbacks for an owner."
  @spec facet(t(), owner()) :: module() | nil
  def facet(%__MODULE__{} = manifest, owner) when owner in @owners,
    do: Map.fetch!(manifest, owner)

  @doc "Returns the declaration options assigned to one callback owner."
  @spec options_for(t(), owner(), keyword()) :: keyword()
  def options_for(%__MODULE__{option_keys: option_keys}, owner, options)
      when owner in @owners and is_list(options) do
    if not Keyword.keyword?(options) do
      raise ArgumentError, "Plugin declaration options must be a keyword list"
    end

    case {map_size(option_keys), Map.fetch(option_keys, owner)} do
      {0, _result} -> options
      {_size, {:ok, keys}} -> Keyword.take(options, keys)
      {_size, :error} -> []
    end
  end

  @doc "Validates static manifest metadata and common declaration options."
  @spec validate(t(), keyword()) :: {:ok, t()} | {:error, Error.ValidationError.t()}
  def validate(%__MODULE__{} = manifest, options) do
    with :ok <- validate_module(manifest.module),
         true <- Keyword.keyword?(options),
         :ok <- validate_vsn(manifest.vsn),
         :ok <- validate_facets(manifest),
         :ok <- validate_option_keys(manifest, options),
         :ok <- validate_static_options(options) do
      {:ok, manifest}
    else
      false -> invalid_manifest(manifest, options)
      {:error, _reason} = error -> error
    end
  end

  def validate(manifest, options),
    do: invalid_manifest(manifest, options)

  defp validate_module(module) when is_atom(module) and module not in [nil, true, false], do: :ok
  defp validate_module(module), do: invalid("Plugin package module is invalid", %{module: module})

  defp validate_vsn(vsn) when is_integer(vsn) and vsn > 0, do: :ok
  defp validate_vsn(vsn), do: invalid("Plugin package version must be positive", %{vsn: vsn})

  defp validate_facets(manifest) do
    facets = Enum.map(@owners, &Map.fetch!(manifest, &1))

    cond do
      Enum.all?(facets, &is_nil/1) ->
        invalid("Plugin must define at least one callback", %{plugin: manifest.module})

      Enum.any?(facets, &(not is_nil(&1) and &1 != manifest.module)) ->
        invalid = Enum.find(facets, &(not is_nil(&1) and &1 != manifest.module))

        invalid("Plugin callbacks must belong to the Plugin module", %{
          plugin: manifest.module,
          facet: invalid
        })

      true ->
        :ok
    end
  end

  defp validate_option_keys(%__MODULE__{option_keys: option_keys} = manifest, options)
       when is_map(option_keys) do
    owner_keys = Map.keys(option_keys)
    option_keys_in_order = Keyword.keys(options)
    duplicate_options = duplicate_keys(option_keys_in_order)

    invalid_owner = Enum.find(owner_keys, &(&1 not in @owners))

    invalid_keys =
      Enum.find_value(option_keys, fn {owner, keys} ->
        if is_list(keys) and Enum.all?(keys, &is_atom/1) and Enum.uniq(keys) == keys,
          do: nil,
          else: {owner, keys}
      end)

    unselected_owner =
      Enum.find(owner_keys, &(&1 in @owners and is_nil(Map.fetch!(manifest, &1))))

    assigned = option_keys |> Map.values() |> List.flatten() |> MapSet.new()
    unassigned = options |> Keyword.keys() |> Enum.reject(&MapSet.member?(assigned, &1))

    cond do
      duplicate_options != [] ->
        invalid("Plugin declaration options must be unique", %{options: duplicate_options})

      not is_nil(invalid_owner) ->
        invalid("Plugin option mapping has an unknown owner", %{
          owner: invalid_owner,
          owners: @owners
        })

      invalid_keys ->
        invalid("Plugin option mapping must contain unique atom keys", %{
          mapping: invalid_keys
        })

      unselected_owner ->
        invalid("Plugin option mapping names an unselected facet", %{
          owner: unselected_owner
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
    case Jido.Authoring.validate_static(options) do
      :ok ->
        :ok

      {:error, reason} ->
        invalid("Plugin declaration options must be static data", %{
          reason: Exception.message(reason)
        })
    end
  end

  defp duplicate_keys(keys) do
    frequencies = Enum.frequencies(keys)

    keys
    |> Enum.filter(&(Map.fetch!(frequencies, &1) > 1))
    |> Enum.uniq()
  end

  defp invalid_manifest(manifest, options) do
    invalid("Plugin manifest or declaration options are invalid", %{
      manifest: manifest,
      options: options
    })
  end

  defp invalid(message, details) do
    {:error, Error.validation_error(message, kind: :config, details: details)}
  end
end

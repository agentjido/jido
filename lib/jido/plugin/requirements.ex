defmodule Jido.Plugin.Requirements do
  @moduledoc """
  Validates plugin requirements at agent creation time.

  Plugins can declare requirements in their configuration:
  - `{:config, key}` - Ensure resolved config has this key with non-nil value
  - `{:app, app_name}` - Ensure the OTP application is available
  - `{:plugin, plugin_name}` - Ensure another mounted plugin has this name

  ## Example

      defmodule MyApp.SlackPlugin do
        use Jido.Plugin,
          name: "slack",
          requires: [
            {:config, :token},
            {:config, :channel},
            {:app, :req}
          ]
      end

  If requirements are not met, agent compilation will fail with a descriptive error.
  """

  alias Jido.Plugin.Instance

  @type requirement :: {:config, atom()} | {:app, atom()} | {:plugin, String.t() | atom()}
  @type context :: %{
          mounted_plugins: [Instance.t()],
          resolved_config: map()
        }

  @doc """
  Validates requirements for a single plugin instance.

  ## Parameters

  - `instance` - The plugin instance with manifest containing requirements
  - `context` - Map with `:mounted_plugins` and `:resolved_config`

  ## Returns

  - `{:ok, :valid}` - All requirements are met
  - `{:error, missing_requirements}` - List of unmet requirements

  ## Examples

      iex> validate_requirements(slack_instance, context)
      {:ok, :valid}

      iex> validate_requirements(slack_instance, %{mounted_plugins: [], resolved_config: %{}})
      {:error, [{:config, :token}, {:app, :req}]}
  """
  @spec validate_requirements(Instance.t(), context()) ::
          {:ok, :valid} | {:error, [requirement()]}
  def validate_requirements(%Instance{} = instance, context) do
    requirements = instance.manifest.requires || []
    resolved_config = context[:resolved_config] || instance.config
    mounted_plugin_names = get_mounted_plugin_names(context[:mounted_plugins] || [])

    missing =
      requirements
      |> Enum.reject(fn req ->
        check_requirement(req, resolved_config, mounted_plugin_names)
      end)

    if missing == [] do
      {:ok, :valid}
    else
      {:error, missing}
    end
  end

  @doc """
  Validates requirements for all plugin instances.

  Returns a single error listing all missing requirements grouped by plugin.

  ## Parameters

  - `instances` - List of plugin instances
  - `config_map` - Map of `state_key => resolved_config` for each plugin

  ## Returns

  - `{:ok, :valid}` - All requirements for all plugins are met
  - `{:error, missing_by_plugin}` - Map of plugin name => missing requirements

  ## Examples

      iex> validate_all_requirements(instances, config_map)
      {:ok, :valid}

      iex> validate_all_requirements([slack_instance], %{})
      {:error, %{"slack" => [{:config, :token}]}}
  """
  @spec validate_all_requirements([Instance.t()], map()) ::
          {:ok, :valid} | {:error, %{String.t() => [requirement()]}}
  def validate_all_requirements(instances, config_map) do
    mounted_plugin_names = get_mounted_plugin_names(instances)

    missing_by_plugin =
      instances
      |> Enum.reduce(%{}, fn instance, acc ->
        resolved_config = Map.get(config_map, instance.state_key, instance.config)

        case validate_requirements_internal(
               instance.manifest.requires || [],
               resolved_config,
               mounted_plugin_names
             ) do
          [] ->
            acc

          missing ->
            plugin_name = instance.manifest.name
            Map.put(acc, plugin_name, missing)
        end
      end)

    if missing_by_plugin == %{} do
      {:ok, :valid}
    else
      {:error, missing_by_plugin}
    end
  end

  @doc """
  Formats missing requirements into a human-readable error message.

  ## Examples

      iex> format_error(%{"slack" => [{:config, :token}, {:app, :req}]})
      "Missing requirements for plugins: slack requires {:config, :token}, {:app, :req}"
  """
  @spec format_error(%{String.t() => [requirement()]}) :: String.t()
  def format_error(missing_by_plugin) do
    parts =
      Enum.map_join(missing_by_plugin, "; ", fn {plugin_name, requirements} ->
        reqs_str = Enum.map_join(requirements, ", ", &inspect/1)
        "#{plugin_name} requires #{reqs_str}"
      end)

    "Missing requirements for plugins: #{parts}"
  end

  # Internal validation that returns list of missing requirements
  defp validate_requirements_internal(requirements, resolved_config, mounted_plugin_names) do
    Enum.reject(requirements, fn req ->
      check_requirement(req, resolved_config, mounted_plugin_names)
    end)
  end

  defp check_requirement({:config, key}, resolved_config, _mounted_plugins) do
    value = Map.get(resolved_config, key)
    value != nil
  end

  defp check_requirement({:app, app_name}, _resolved_config, _mounted_plugins) do
    Application.spec(app_name) != nil
  end

  defp check_requirement({:plugin, plugin_name}, _resolved_config, mounted_plugin_names) do
    plugin_name_str = to_string(plugin_name)
    plugin_name_str in mounted_plugin_names
  end

  defp check_requirement(_unknown, _resolved_config, _mounted_plugins) do
    true
  end

  defp get_mounted_plugin_names(instances) do
    Enum.map(instances, fn instance -> instance.manifest.name end)
  end
end

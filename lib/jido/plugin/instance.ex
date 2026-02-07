defmodule Jido.Plugin.Instance do
  @moduledoc """
  Represents a normalized plugin instance attached to an agent.

  Supports multiple instances of the same plugin with different configurations
  via the `as:` option. Each instance gets a unique derived state_key and
  route_prefix based on the `as:` value.

  ## Fields

  - `module` - The plugin module
  - `as` - Optional instance alias atom (e.g., `:support`, `:sales`)
  - `config` - Resolved config map (overrides from agent declaration)
  - `manifest` - The plugin's manifest struct
  - `state_key` - Derived state key (e.g., `:slack` or `:slack_support` if `as: :support`)
  - `route_prefix` - Derived route prefix (e.g., `"slack"` or `"support.slack"`)

  ## Examples

      # Single instance (no alias)
      Instance.new(MyPlugin)
      Instance.new({MyPlugin, %{token: "abc"}})

      # Multiple instances with aliases
      Instance.new({MyPlugin, as: :support, token: "support-token"})
      Instance.new({MyPlugin, as: :sales, token: "sales-token"})
  """

  alias Jido.Plugin.Config

  @schema Zoi.struct(
            __MODULE__,
            %{
              module: Zoi.atom(description: "The plugin module"),
              as: Zoi.atom(description: "Optional instance alias") |> Zoi.optional(),
              config: Zoi.map(description: "Resolved configuration") |> Zoi.default(%{}),
              manifest: Zoi.any(description: "The plugin's manifest struct"),
              state_key: Zoi.atom(description: "Derived state key for agent state"),
              route_prefix: Zoi.string(description: "Derived route prefix for signal routing")
            },
            coerce: true
          )

  @type t :: unquote(Zoi.type_spec(@schema))
  @enforce_keys Zoi.Struct.enforce_keys(@schema)
  defstruct Zoi.Struct.struct_fields(@schema)

  @doc "Returns the Zoi schema for Instance."
  @spec schema() :: Zoi.schema()
  def schema, do: @schema

  @doc """
  Creates a new Instance from a plugin declaration.

  Config resolution happens during instance creation:
  1. Base config from `Application.get_env(otp_app, plugin_module)`
  2. Per-agent overrides from the declaration
  3. Validation against the plugin's `config_schema` if present

  ## Input Formats

  - `PluginModule` - Module with no config
  - `{PluginModule, %{key: value}}` - Module with config map
  - `{PluginModule, [key: value]}` - Module with keyword list (may include `:as`)

  The `:as` option is extracted from the config and used to derive
  unique state_key and route_prefix for the instance.

  ## Examples

      iex> Instance.new(MyPlugin)
      %Instance{module: MyPlugin, as: nil, state_key: :my_plugin, ...}

      iex> Instance.new({MyPlugin, as: :support, token: "abc"})
      %Instance{module: MyPlugin, as: :support, state_key: :my_plugin_support, ...}

      iex> Instance.new({MyPlugin, %{token: "abc"}})
      %Instance{module: MyPlugin, as: nil, config: %{token: "abc"}, ...}
  """
  @spec new(module() | {module(), map() | keyword()}) :: t()
  def new(plugin_declaration) do
    {module, as_opt, overrides} = normalize_declaration(plugin_declaration)

    if function_exported?(module, :singleton?, 0) and module.singleton?() and as_opt != nil do
      raise ArgumentError,
            "Cannot alias singleton plugin #{inspect(module)} with `as: #{inspect(as_opt)}`"
    end

    manifest = module.manifest()
    base_state_key = manifest.state_key
    base_name = manifest.name

    resolved_config = Config.resolve_config!(module, overrides)

    state_key = derive_state_key(base_state_key, as_opt)
    route_prefix = derive_route_prefix(base_name, as_opt)

    %__MODULE__{
      module: module,
      as: as_opt,
      config: resolved_config,
      manifest: manifest,
      state_key: state_key,
      route_prefix: route_prefix
    }
  end

  @doc """
  Derives the state key from the base key and optional `as:` alias.

  ## Examples

      iex> derive_state_key(:slack, nil)
      :slack

      iex> derive_state_key(:slack, :support)
      :slack_support
  """
  @spec derive_state_key(atom(), atom() | nil) :: atom()
  def derive_state_key(base_key, nil), do: base_key

  def derive_state_key(base_key, as_alias) when is_atom(as_alias) do
    String.to_atom("#{base_key}_#{as_alias}")
  end

  @doc """
  Derives the route prefix from the plugin name and optional `as:` alias.

  ## Examples

      iex> derive_route_prefix("slack", nil)
      "slack"

      iex> derive_route_prefix("slack", :support)
      "support.slack"
  """
  @spec derive_route_prefix(String.t(), atom() | nil) :: String.t()
  def derive_route_prefix(base_name, nil), do: base_name

  def derive_route_prefix(base_name, as_alias) when is_atom(as_alias) do
    "#{as_alias}.#{base_name}"
  end

  # Normalizes plugin declaration to {module, as_option, config_map}
  defp normalize_declaration(module) when is_atom(module) do
    {module, nil, %{}}
  end

  defp normalize_declaration({module, opts}) when is_list(opts) do
    {as_opt, rest} = Keyword.pop(opts, :as)
    config = Map.new(rest)
    {module, as_opt, config}
  end

  defp normalize_declaration({module, config}) when is_map(config) do
    {module, nil, config}
  end
end

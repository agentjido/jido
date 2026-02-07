defmodule Jido.Agent.DefaultPlugins do
  @moduledoc """
  Resolves default plugin lists for agents.

  Default plugins are framework-provided singleton plugins that are automatically
  included in agents. They can be customized at three levels:

  1. **Package level** — Jido ships sensible defaults
  2. **Jido instance level** — `use Jido, default_plugins: [...]` or app config
  3. **Agent level** — `default_plugins: %{state_key: false | Module | {Module, config}}`

  ## Framework Defaults

  The framework provides these default plugins:

      [Jido.Thread.Plugin, Jido.Identity.Plugin, Jido.Memory.Plugin]

  ## Instance-Level Override

      # In use Jido macro
      use Jido, otp_app: :my_app, default_plugins: [MyApp.CustomThreadPlugin]

      # Or via app config
      config :my_app, MyApp.Jido, default_plugins: [MyApp.CustomThreadPlugin]

  ## Agent-Level Override

  Agents use a map keyed by the default plugin's `state_key` atom:

      use Jido.Agent,
        name: "my_agent",
        default_plugins: %{__thread__: false}

  To replace a default with a custom implementation:

      use Jido.Agent,
        name: "my_agent",
        default_plugins: %{__thread__: MyApp.CustomThreadPlugin}

  Or with configuration:

      use Jido.Agent,
        name: "my_agent",
        default_plugins: %{__thread__: {MyApp.CustomThreadPlugin, %{max_entries: 100}}}

  Or disable all defaults:

      use Jido.Agent, name: "bare", default_plugins: false
  """

  @package_defaults [Jido.Thread.Plugin, Jido.Identity.Plugin, Jido.Memory.Plugin]

  @doc "Returns the framework's default plugin list."
  @spec package_defaults() :: [module()]
  def package_defaults, do: @package_defaults

  @doc """
  Resolves default plugins for a Jido instance.

  This is a macro because `Application.compile_env/3` must be called in the
  module body of the caller, not inside a function.

  Priority (highest wins):
  1. Explicit `default_plugins` option passed to `use Jido`
  2. App config: `config :otp_app, JidoModule, default_plugins: [...]`
  3. Framework defaults
  """
  defmacro resolve_instance_defaults(otp_app, jido_module, explicit_defaults) do
    package_defaults = @package_defaults

    quote do
      cond do
        unquote(explicit_defaults) != nil ->
          unquote(explicit_defaults)

        true ->
          app_config = Application.compile_env(unquote(otp_app), unquote(jido_module), [])
          Keyword.get(app_config, :default_plugins, unquote(Macro.escape(package_defaults)))
      end
    end
  end

  @doc """
  Applies agent-level overrides to a list of default plugins.

  ## Parameters

  - `defaults` - The resolved default plugin list (from instance or framework)
  - `overrides` - Agent-level override specification

  ## Override Shapes

  - `nil` — no overrides, use all defaults as-is
  - `false` — disable all defaults
  - `%{state_key => false}` — exclude the default plugin with that state_key
  - `%{state_key => Module}` — replace with a different module
  - `%{state_key => {Module, config}}` — replace with module and config
  """
  @spec apply_agent_overrides([module() | {module(), map()}], nil | false | map()) ::
          [module() | {module(), map() | keyword()}]
  def apply_agent_overrides(defaults, nil), do: defaults
  def apply_agent_overrides(_defaults, false), do: []

  def apply_agent_overrides(defaults, overrides) when is_map(overrides) do
    default_state_keys = build_state_key_index(defaults)
    validate_override_keys!(overrides, default_state_keys)

    Enum.flat_map(defaults, fn plugin_decl ->
      mod = extract_module(plugin_decl)
      state_key = mod.state_key()

      case Map.get(overrides, state_key) do
        nil -> [plugin_decl]
        false -> []
        replacement when is_atom(replacement) -> [replacement]
        {replacement, config} when is_atom(replacement) -> [{replacement, config}]
      end
    end)
  end

  defp build_state_key_index(defaults) do
    Enum.map(defaults, fn
      mod when is_atom(mod) -> {mod.state_key(), mod}
      {mod, _config} -> {mod.state_key(), mod}
    end)
    |> Map.new(fn {key, mod} -> {key, mod} end)
  end

  defp validate_override_keys!(overrides, default_state_keys) do
    invalid_keys = Map.keys(overrides) -- Map.keys(default_state_keys)

    if invalid_keys != [] do
      valid_keys = Map.keys(default_state_keys) |> Enum.map(&inspect/1) |> Enum.join(", ")

      raise CompileError,
        description:
          "Invalid default_plugins override keys: #{inspect(invalid_keys)}. " <>
            "Valid keys are: #{valid_keys}. " <>
            "To add new plugins, use the `plugins:` option instead."
    end
  end

  defp extract_module(mod) when is_atom(mod), do: mod
  defp extract_module({mod, _config}), do: mod
end

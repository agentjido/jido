defmodule Jido.Agent.Plugin do
  @moduledoc """
  Pure Agent-owned facet of a `Jido.Plugin` package.

  An Agent Plugin can own one field in the complete Agent state map and one or
  more Directive types. After executable success, it can update only its owned
  field from its owned Directives.
  """

  alias Jido.Agent.Plugin.Spec
  alias Jido.Plugin.Error, as: PluginError
  alias Jido.Plugin.Normalizer

  @type state_spec :: :none | {atom(), Zoi.schema()}

  @doc "Defines an Agent-owned Plugin facet."
  defmacro __using__(_opts) do
    quote location: :keep do
      @behaviour Jido.Agent.Plugin

      @doc false
      def __jido_plugin_facet__, do: :agent
    end
  end

  @callback state_spec(opts :: keyword()) :: state_spec() | {:error, term()}
  @callback directives(opts :: keyword()) :: [module()] | {:error, term()}
  @callback validate_directive(directive :: struct(), opts :: keyword()) ::
              {:ok, struct()} | {:error, term()}
  @callback update_state(state :: term(), directives :: [struct()], opts :: keyword()) ::
              {:ok, term()} | {:error, term()}

  @optional_callbacks state_spec: 1,
                      directives: 1,
                      validate_directive: 2,
                      update_state: 3

  @doc false
  @spec compose_schema(Zoi.schema(), [Jido.Plugin.declaration()] | [Jido.Plugin.Spec.t()]) ::
          {:ok, Zoi.schema()} | {:error, term()}
  def compose_schema(%Zoi.Types.Map{fields: fields} = domain_schema, declarations)
      when is_list(fields) do
    with {:ok, specs} <- Normalizer.normalize_all(declarations),
         agent_specs = specs(specs),
         :ok <- state_key_conflicts(fields, agent_specs) do
      plugin_fields =
        agent_specs
        |> Enum.reject(&is_nil(&1.state_key))
        |> Map.new(fn %Spec{state_key: key, state_schema: schema} -> {key, schema} end)

      extended = Zoi.extend(domain_schema, plugin_fields)
      {:ok, %{domain_schema | fields: extended.fields}}
    end
  end

  def compose_schema(schema, _declarations) do
    PluginError.validation("Agent domain schema must be a field-based Zoi object", %{
      schema: schema
    })
  end

  @doc false
  @spec specs([Jido.Plugin.Spec.t()]) :: [Spec.t()]
  def specs(plugin_specs) do
    Enum.flat_map(plugin_specs, fn
      %{agent: %Spec{} = spec} -> [spec]
      %Spec{} = spec -> [spec]
      _spec -> []
    end)
  end

  @doc false
  @spec directive_owner([Spec.t()], struct()) :: Spec.t() | nil
  def directive_owner(specs, %{__struct__: directive_module}) do
    Enum.find(specs, &(directive_module in &1.directive_modules))
  end

  def directive_owner(_specs, _directive), do: nil

  @doc false
  @spec validate_directive(Spec.t(), struct()) :: {:ok, struct()} | {:error, term()}
  def validate_directive(%Spec{} = spec, %{__struct__: directive_module} = directive) do
    PluginError.safe_apply(
      spec.package,
      spec.module,
      :validate_directive,
      [directive, spec.options],
      "Agent Plugin Directive validation failed"
    )
    |> case do
      {:ok, %{__struct__: ^directive_module} = validated} ->
        {:ok, validated}

      {:ok, %{__struct__: validated_module}} ->
        PluginError.invalid_callback(
          "Agent Plugin validate_directive/2 changed Directive type",
          spec.package,
          spec.module,
          %{expected: directive_module, actual: validated_module}
        )

      {:error, _reason} = error ->
        error

      result ->
        PluginError.invalid_callback(
          "Agent Plugin validate_directive/2 returned an invalid result",
          spec.package,
          spec.module,
          %{result: result}
        )
    end
  end

  defp state_key_conflicts(fields, specs) do
    domain_keys = MapSet.new(Keyword.keys(fields))

    case Enum.find(specs, &MapSet.member?(domain_keys, &1.state_key)) do
      nil ->
        :ok

      spec ->
        PluginError.validation("Plugin-owned Agent state key conflicts with the domain schema", %{
          plugin: spec.package,
          state_key: spec.state_key
        })
    end
  end
end

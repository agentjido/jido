defmodule Jido.Agent.Plugin do
  @moduledoc """
  Pure Agent-owned facet of a `Jido.Plugin` package.

  Before route selection, an Agent Plugin can inspect the complete Agent state,
  reject a Signal, or prepare one portable package-owned input for execution.
  It cannot change the Signal, caller context, route, or Agent state.

  An Agent Plugin can also own one field in the complete Agent state map and
  one or more Directive types. After executable success, it can inspect the
  current candidate state and validated Directives. It can reduce only its
  owned field.
  """

  alias Jido.Agent
  alias Jido.Agent.Plugin.{Preparation, Reduction, Spec}
  alias Jido.Plugin.Input
  alias Jido.Plugin.Error, as: PluginError
  alias Jido.Plugin.Normalizer
  alias Jido.Signal

  @type state_spec :: :none | {atom(), Zoi.schema()}

  @doc "Defines an Agent-owned Plugin facet."
  defmacro __using__(_opts) do
    quote location: :keep do
      @behaviour Jido.Agent.Plugin

      @doc false
      def __jido_plugin_facet__, do: :agent
    end
  end

  @callback prepare(preparation :: Preparation.t(), opts :: keyword()) ::
              {:ok, term()} | {:error, term()}
  @callback state_spec(opts :: keyword()) :: state_spec() | {:error, term()}
  @callback directives(opts :: keyword()) :: [module()] | {:error, term()}
  @callback reduce(reduction :: Reduction.t(), opts :: keyword()) ::
              {:ok, term()} | {:error, term()}

  @optional_callbacks prepare: 2,
                      state_spec: 1,
                      directives: 1,
                      reduce: 2

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
  @spec prepares?([Jido.Plugin.Spec.t()] | [Spec.t()]) :: boolean()
  def prepares?(plugin_specs) do
    plugin_specs
    |> specs()
    |> Enum.any?(&function_exported?(&1.module, :prepare, 2))
  end

  @doc false
  @spec prepare(Agent.instance(), Signal.t(), [Jido.Plugin.Spec.t()] | [Spec.t()]) ::
          {:ok, %{optional(module()) => Input.t()}} | {:error, term()}
  def prepare(%Agent{} = agent, %Signal{} = signal, plugin_specs) when is_list(plugin_specs) do
    plugin_specs
    |> specs()
    |> Enum.reduce_while({:ok, %{}}, fn spec, {:ok, inputs} ->
      case prepare_one(agent, signal, spec) do
        :none ->
          {:cont, {:ok, inputs}}

        {:ok, input} ->
          package_input = %Input{} |> Input.put_prepared(input)
          {:cont, {:ok, Map.put(inputs, spec.package, package_input)}}

        {:error, _reason} = error ->
          {:halt, error}
      end
    end)
  end

  @doc false
  @spec directive_owner([Spec.t()], struct()) :: Spec.t() | nil
  def directive_owner(specs, %{__struct__: directive_module}) do
    Enum.find(specs, &(directive_module in &1.directive_modules))
  end

  def directive_owner(_specs, _directive), do: nil

  @doc false
  @spec validate_legacy_directive(Spec.t(), struct()) :: {:ok, struct()} | {:error, term()}
  def validate_legacy_directive(%Spec{} = spec, %{__struct__: directive_module} = directive) do
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

  defp prepare_one(agent, signal, %Spec{} = spec) do
    if function_exported?(spec.module, :prepare, 2) do
      preparation = %Preparation{
        plugin: spec.package,
        agent_id: agent.id,
        agent_module: agent.module,
        agent_state: agent.state,
        signal: signal,
        plugin_state: plugin_state(agent.state, spec.state_key)
      }

      PluginError.safe_apply(
        spec.package,
        spec.module,
        :prepare,
        [preparation, spec.options],
        "Agent Plugin preparation failed"
      )
      |> validate_preparation_result(spec)
    else
      :none
    end
  end

  defp validate_preparation_result({:ok, input}, spec) do
    case Jido.PortableTerm.validate(input, [:plugin_inputs, spec.package, :prepared]) do
      :ok ->
        {:ok, input}

      {:error, path} ->
        PluginError.invalid_callback(
          "Agent Plugin prepare/2 returned a non-portable input",
          spec.package,
          spec.module,
          %{code: :non_portable_term, path: path}
        )
    end
  end

  defp validate_preparation_result({:error, _reason} = error, _spec), do: error

  defp validate_preparation_result(result, spec) do
    PluginError.invalid_callback(
      "Agent Plugin prepare/2 returned an invalid result",
      spec.package,
      spec.module,
      %{result: result}
    )
  end

  defp plugin_state(_state, nil), do: nil
  defp plugin_state(state, key), do: Map.get(state, key)

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

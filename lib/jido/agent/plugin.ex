defmodule Jido.Agent.Plugin do
  @moduledoc """
  Pure Agent-owned facet of a `Jido.Plugin` package.

  This facet can declare one state field and owned Directive types. It can
  prepare bounded Turn input and contribute owned state and Directives after
  executable success. It receives no runtime handle, persistence adapter, or
  Topology control value.
  """

  alias Jido.Agent
  alias Jido.Agent.Command
  alias Jido.Agent.Plugin.{Contribution, Preparation, Spec, Transition}
  alias Jido.Plugin.Error, as: PluginError
  alias Jido.Plugin.Normalizer

  @type state_spec :: :none | {atom(), Zoi.schema()}
  @type result :: {:ok, map(), [struct()]} | {:error, term()}

  @doc "Defines an Agent-owned Plugin facet."
  defmacro __using__(_opts) do
    quote location: :keep do
      @behaviour Jido.Agent.Plugin

      @doc false
      def __jido_plugin_facet__, do: :agent
    end
  end

  @callback state_spec(opts :: keyword()) :: state_spec() | {:error, term()}
  @callback observes(opts :: keyword()) :: [atom()] | {:error, term()}
  @callback prepare(preparation :: Preparation.t(), opts :: keyword()) ::
              {:ok, Preparation.t()} | {:error, term()}
  @callback contribute(transition :: Transition.t(), opts :: keyword()) ::
              {:ok, Contribution.t()} | {:error, term()}
  @callback directives(opts :: keyword()) :: [module()] | {:error, term()}
  @callback validate_directive(directive :: struct(), opts :: keyword()) ::
              {:ok, struct()} | {:error, term()}

  @optional_callbacks state_spec: 1,
                      observes: 1,
                      prepare: 2,
                      contribute: 2,
                      directives: 1,
                      validate_directive: 2

  @doc false
  @spec compose_schema(Zoi.schema(), [Jido.Plugin.declaration()] | [Jido.Plugin.Spec.t()]) ::
          {:ok, Zoi.schema()} | {:error, term()}
  def compose_schema(%Zoi.Types.Map{fields: fields} = domain_schema, declarations)
      when is_list(fields) do
    with {:ok, specs} <- Normalizer.normalize_all(declarations),
         :ok <- state_key_conflicts(fields, specs) do
      plugin_fields =
        Enum.reduce(specs, %{}, fn
          %{agent: %Spec{state_key: key, state_schema: schema}}, acc when not is_nil(key) ->
            Map.put(acc, key, schema)

          _spec, acc ->
            acc
        end)

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
  @spec prepare_evaluation(
          Command.t(),
          Jido.Signal.t(),
          [Jido.Plugin.declaration()] | [Jido.Plugin.Spec.t()]
        ) ::
          {:ok, Command.t(), [Jido.Plugin.Spec.t()], %{optional(module()) => term()}}
          | {:error, term()}
  def prepare_evaluation(%Command{} = command, %Jido.Signal{} = source_signal, declarations) do
    with {:ok, command} <- Command.validate(command),
         {:ok, specs} <- Normalizer.normalize_all(declarations),
         {:ok, command, inputs} <- prepare_all(command, source_signal, specs) do
      {:ok, command, specs, inputs}
    end
  end

  @doc false
  @spec protect_state(result(), map(), [Jido.Plugin.Spec.t()]) :: result()
  def protect_state({:ok, state, _directives} = result, original_state, specs) do
    case changed_keys(original_state, state, state_keys(specs)) do
      [] ->
        result

      keys ->
        {:error,
         PluginError.execution(
           "Agent executable changed Plugin-owned state",
           :core,
           __MODULE__,
           %{keys: keys, code: :plugin_state_owner_violation}
         )}
    end
  end

  def protect_state(result, _original_state, _specs), do: result

  @doc false
  @spec update_state(result(), [Jido.Plugin.Spec.t()]) :: result()
  def update_state({:ok, _state, _directives} = result, specs) do
    Enum.reduce_while(specs, result, fn
      %{agent: %Spec{legacy?: true}} = plugin_spec, current ->
        contribute_one(plugin_spec, current, nil, nil, nil, %{})

      _plugin_spec, current ->
        {:cont, current}
    end)
  end

  def update_state(result, _specs), do: result

  @doc false
  @spec contribute(
          result(),
          Agent.t(),
          Jido.Signal.t(),
          Jido.Signal.t(),
          map(),
          [Jido.Plugin.Spec.t()]
        ) :: result()
  def contribute(
        {:ok, state, directives},
        %Agent{} = agent,
        %Jido.Signal{} = source_signal,
        %Jido.Signal{} = effective_signal,
        inputs,
        specs
      )
      when is_map(inputs) and is_list(specs) do
    Enum.reduce_while(specs, {:ok, state, directives}, fn plugin_spec, result ->
      contribute_one(
        plugin_spec,
        result,
        agent,
        source_signal,
        effective_signal,
        inputs
      )
    end)
  end

  def contribute(result, _agent, _source_signal, _effective_signal, _inputs, _specs), do: result

  @doc false
  @spec state_keys([Jido.Plugin.Spec.t()]) :: [atom()]
  def state_keys(specs) do
    specs
    |> Enum.map(fn
      %{agent: %Spec{state_key: key}} -> key
      _spec -> nil
    end)
    |> Enum.reject(&is_nil/1)
  end

  @doc false
  @spec directive_owner([Jido.Plugin.Spec.t()], struct()) :: Jido.Plugin.Spec.t() | nil
  def directive_owner(specs, %{__struct__: directive_module}) do
    Enum.find(specs, fn
      %{agent: %Spec{directive_modules: modules}} -> directive_module in modules
      _spec -> false
    end)
  end

  def directive_owner(_specs, _directive), do: nil

  @doc false
  @spec validate_directive(Jido.Plugin.Spec.t(), struct()) :: {:ok, struct()} | {:error, term()}
  def validate_directive(
        %{agent: %Spec{} = spec},
        %{__struct__: directive_module} = directive
      ) do
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

  defp prepare_all(command, source_signal, specs) do
    Enum.reduce_while(specs, {:ok, command, %{}}, fn plugin_spec, {:ok, current, inputs} ->
      case prepare_one(current, source_signal, inputs, plugin_spec) do
        {:ok, prepared, prepared_inputs} -> {:cont, {:ok, prepared, prepared_inputs}}
        {:error, _reason} = error -> {:halt, error}
      end
    end)
  end

  defp prepare_one(command, _source_signal, inputs, %{agent: nil}),
    do: {:ok, command, inputs}

  defp prepare_one(command, source_signal, inputs, %{agent: %Spec{legacy?: true} = spec}) do
    cond do
      function_exported?(spec.module, :prepare_turn, 2) ->
        prepare_bounded(command, source_signal, inputs, spec, :prepare_turn)

      function_exported?(spec.module, :prepare, 2) ->
        prepare_legacy(command, inputs, spec)

      true ->
        {:ok, command, inputs}
    end
  end

  defp prepare_one(command, source_signal, inputs, %{agent: %Spec{} = spec}) do
    if function_exported?(spec.module, :prepare, 2),
      do: prepare_bounded(command, source_signal, inputs, spec, :prepare),
      else: {:ok, command, inputs}
  end

  defp prepare_bounded(command, source_signal, inputs, spec, callback) do
    with {:ok, projection} <- agent_projection(command.agent, spec),
         preparation = %Preparation{
           plugin: spec.package,
           agent_id: command.agent.id,
           agent_module: command.agent.module,
           agent_state: projection,
           plugin_state: plugin_state(command.agent.state, spec.state_key),
           source_signal: source_signal,
           effective_signal: command.signal,
           context: command.context,
           input: Map.get(inputs, spec.package)
         },
         {:ok, preparation} <- Preparation.validate(preparation),
         result <-
           PluginError.safe_apply(
             spec.package,
             spec.module,
             callback,
             [preparation, spec.options],
             "Agent Plugin preparation failed"
           ),
         {:ok, prepared} <- validate_preparation_result(result, preparation, spec, callback),
         {:ok, command} <-
           Command.validate(%{
             command
             | signal: prepared.effective_signal,
               context: prepared.context
           }) do
      {:ok, command, Map.put(inputs, spec.package, prepared.input)}
    end
  end

  defp prepare_legacy(command, inputs, spec) do
    PluginError.safe_apply(
      spec.package,
      spec.module,
      :prepare,
      [command, spec.options],
      "Legacy Plugin prepare/2 failed"
    )
    |> case do
      {:ok, %Command{} = prepared} ->
        with {:ok, prepared} <- validate_command_agent(prepared, command, spec) do
          {:ok, prepared, inputs}
        end

      {:error, _reason} = error ->
        error

      result ->
        PluginError.invalid_callback(
          "Legacy Plugin prepare/2 returned an invalid result",
          spec.package,
          spec.module,
          %{result: result}
        )
    end
  end

  defp validate_preparation_result({:ok, %Preparation{} = prepared}, original, spec, callback) do
    with {:ok, prepared} <- Preparation.validate(prepared),
         :ok <- unchanged_preparation_fields(prepared, original, spec, callback),
         :ok <- portable(prepared.input, [:plugin_inputs, spec.package], spec) do
      {:ok, prepared}
    end
  end

  defp validate_preparation_result({:error, _reason} = error, _original, _spec, _callback),
    do: error

  defp validate_preparation_result(result, _original, spec, callback) do
    PluginError.invalid_callback(
      "Agent Plugin preparation returned an invalid result",
      spec.package,
      spec.module,
      %{callback: callback, result: result}
    )
  end

  defp unchanged_preparation_fields(prepared, original, spec, callback) do
    changed =
      [:plugin, :agent_id, :agent_module, :agent_state, :plugin_state, :source_signal]
      |> Enum.filter(&(Map.fetch!(prepared, &1) != Map.fetch!(original, &1)))

    if changed == [] do
      :ok
    else
      PluginError.invalid_callback(
        "Agent Plugin preparation changed read-only fields",
        spec.package,
        spec.module,
        %{callback: callback, fields: changed}
      )
    end
  end

  defp validate_command_agent(command, original, spec) do
    with {:ok, command} <- Command.validate(command),
         true <- command.agent == original.agent do
      {:ok, command}
    else
      false ->
        PluginError.invalid_callback(
          "Agent Plugin cannot replace the Agent",
          spec.package,
          spec.module
        )

      {:error, _reason} = error ->
        error
    end
  end

  defp contribute_one(%{agent: nil}, result, _agent, _source, _effective, _inputs),
    do: {:cont, result}

  defp contribute_one(
         %{agent: %Spec{legacy?: true} = spec},
         {:ok, state, directives} = unchanged,
         _agent,
         _source,
         _effective,
         _inputs
       ) do
    if function_exported?(spec.module, :update_state, 3) do
      current = Map.get(state, spec.state_key)
      owned = owned_directives(directives, spec)

      PluginError.safe_apply(
        spec.package,
        spec.module,
        :update_state,
        [current, owned, spec.options],
        "Legacy Plugin update_state/3 failed"
      )
      |> validate_legacy_state(spec, state, directives)
    else
      {:cont, unchanged}
    end
  end

  defp contribute_one(
         %{agent: %Spec{} = spec} = plugin_spec,
         {:ok, state, directives} = unchanged,
         agent,
         source,
         effective,
         inputs
       ) do
    if function_exported?(spec.module, :contribute, 2) do
      with {:ok, before_state} <- agent_projection(agent, spec),
           {:ok, after_state} <- state_projection(state, agent, spec) do
        transition = %Transition{
          plugin: spec.package,
          agent_id: agent.id,
          agent_module: agent.module,
          before_state: before_state,
          after_state: after_state,
          plugin_state: plugin_state(state, spec.state_key),
          input: Map.get(inputs, spec.package),
          source_signal: source,
          effective_signal: effective,
          directives: owned_directives(directives, spec)
        }

        with {:ok, transition} <- Transition.validate(transition) do
          PluginError.safe_apply(
            spec.package,
            spec.module,
            :contribute,
            [transition, spec.options],
            "Agent Plugin contribution failed"
          )
          |> validate_contribution(plugin_spec, state, directives)
        else
          {:error, _reason} = error -> {:halt, error}
        end
      else
        {:error, _reason} = error -> {:halt, error}
      end
    else
      {:cont, unchanged}
    end
  end

  defp validate_legacy_state({:ok, next}, spec, state, directives) do
    case validate_owned_state(next, spec) do
      {:ok, validated} -> {:cont, {:ok, Map.put(state, spec.state_key, validated), directives}}
      {:error, _reason} = error -> {:halt, error}
    end
  end

  defp validate_legacy_state({:error, _reason} = error, _spec, _state, _directives),
    do: {:halt, error}

  defp validate_legacy_state(result, spec, _state, _directives) do
    {:halt,
     PluginError.invalid_callback(
       "Agent Plugin update_state/3 returned an invalid result",
       spec.package,
       spec.module,
       %{result: result}
     )}
  end

  defp validate_contribution(
         {:ok, %Contribution{} = contribution},
         plugin_spec,
         state,
         directives
       ) do
    spec = plugin_spec.agent

    with {:ok, contribution} <- Contribution.validate(contribution),
         :ok <- contribution_owner(contribution, spec),
         {:ok, state} <- contribution_state(contribution.state, state, spec),
         {:ok, added} <- validate_added_directives(contribution.directives, plugin_spec) do
      {:cont, {:ok, state, directives ++ added}}
    else
      {:error, _reason} = error -> {:halt, error}
    end
  end

  defp validate_contribution({:error, _reason} = error, _plugin_spec, _state, _directives),
    do: {:halt, error}

  defp validate_contribution(result, plugin_spec, _state, _directives) do
    spec = plugin_spec.agent

    {:halt,
     PluginError.invalid_callback(
       "Agent Plugin contribute/2 returned an invalid result",
       spec.package,
       spec.module,
       %{result: result}
     )}
  end

  defp contribution_owner(%Contribution{plugin: package}, %Spec{package: package}), do: :ok

  defp contribution_owner(contribution, spec) do
    PluginError.invalid_callback(
      "Agent Plugin contribution changed package identity",
      spec.package,
      spec.module,
      %{actual: contribution.plugin}
    )
  end

  defp contribution_state(:unchanged, state, _spec), do: {:ok, state}

  defp contribution_state({:replace, _value}, _state, %Spec{state_key: nil} = spec) do
    PluginError.invalid_callback(
      "Agent Plugin without state cannot replace Plugin state",
      spec.package,
      spec.module
    )
  end

  defp contribution_state({:replace, value}, state, %Spec{} = spec) do
    with {:ok, validated} <- validate_owned_state(value, spec) do
      {:ok, Map.put(state, spec.state_key, validated)}
    end
  end

  defp validate_owned_state(value, spec) do
    case Zoi.parse(spec.state_schema, value) do
      {:ok, validated} ->
        with :ok <- portable(validated, [:plugin_state, spec.package], spec),
             do: {:ok, validated}

      {:error, errors} ->
        PluginError.invalid_callback(
          "Agent Plugin state is invalid",
          spec.package,
          spec.module,
          %{errors: errors}
        )
    end
  end

  defp validate_added_directives(directives, plugin_spec) do
    Enum.reduce_while(directives, {:ok, []}, fn
      %{__struct__: module} = directive, {:ok, acc} ->
        if module in plugin_spec.agent.directive_modules do
          case validate_directive(plugin_spec, directive) do
            {:ok, validated} -> {:cont, {:ok, [validated | acc]}}
            {:error, _reason} = error -> {:halt, error}
          end
        else
          {:halt,
           PluginError.invalid_callback(
             "Agent Plugin contribution contains a foreign Directive",
             plugin_spec.module,
             plugin_spec.agent.module,
             %{directive: directive}
           )}
        end

      directive, _acc ->
        {:halt,
         PluginError.invalid_callback(
           "Agent Plugin contribution contains an invalid Directive",
           plugin_spec.module,
           plugin_spec.agent.module,
           %{directive: directive}
         )}
    end)
    |> case do
      {:ok, added} -> {:ok, Enum.reverse(added)}
      error -> error
    end
  end

  defp agent_projection(%Agent{schema: %Zoi.Types.Map{fields: fields}} = agent, spec) do
    projection(agent.state, Keyword.keys(fields), spec)
  end

  defp state_projection(state, %Agent{schema: %Zoi.Types.Map{fields: fields}}, spec) do
    projection(state, Keyword.keys(fields), spec)
  end

  defp projection(state, domain_fields, spec) do
    invalid_fields = spec.observations -- domain_fields

    if invalid_fields == [] do
      {:ok, Map.take(state, spec.observations)}
    else
      PluginError.validation("Agent Plugin observes unknown Agent fields", %{
        plugin: spec.package,
        facet: spec.module,
        fields: invalid_fields
      })
    end
  end

  defp state_key_conflicts(fields, specs) do
    domain_keys = MapSet.new(Keyword.keys(fields))

    case Enum.find(specs, fn
           %{agent: %Spec{state_key: key}} when not is_nil(key) ->
             MapSet.member?(domain_keys, key)

           _spec ->
             false
         end) do
      nil ->
        :ok

      plugin_spec ->
        PluginError.validation("Agent Plugin state key conflicts with the Agent domain schema", %{
          plugin: plugin_spec.module,
          state_key: plugin_spec.agent.state_key
        })
    end
  end

  defp owned_directives(directives, %Spec{directive_modules: modules}) do
    Enum.filter(directives, fn
      %{__struct__: module} -> module in modules
      _directive -> false
    end)
  end

  defp changed_keys(before, after_state, keys) when is_map(before) and is_map(after_state) do
    Enum.filter(keys, &(Map.fetch(before, &1) !== Map.fetch(after_state, &1)))
  end

  defp plugin_state(_state, nil), do: nil
  defp plugin_state(state, key), do: Map.get(state, key)

  defp portable(value, path, spec) do
    case Jido.PortableTerm.validate(value, path) do
      :ok ->
        :ok

      {:error, error_path} ->
        PluginError.invalid_callback(
          "Agent Plugin returned a non-portable value",
          spec.package,
          spec.module,
          %{code: :non_portable_term, path: error_path}
        )
    end
  end
end

defmodule Jido.Agent.Plugin.Pipeline do
  @moduledoc false

  alias Jido.Agent
  alias Jido.Agent.Plugin
  alias Jido.Agent.Plugin.{Reduction, Spec}
  alias Jido.Error
  alias Jido.Plugin.Input
  alias Jido.Plugin.Error, as: PluginError
  alias Jido.Signal

  @type result :: {:ok, map(), [struct()]} | {:error, term()}

  @doc false
  @spec run(result(), Agent.instance(), Signal.t(), %{optional(module()) => Input.t()}, [Spec.t()]) ::
          result()
  def run({:ok, state, directives}, %Agent{} = agent, %Signal{} = signal, plugin_inputs, specs)
      when is_map(state) and is_map(plugin_inputs) and is_list(directives) and is_list(specs) do
    run_pipeline(
      {:ok, state, directives},
      agent.state,
      agent.id,
      agent.module,
      signal,
      plugin_inputs,
      specs
    )
  end

  def run({:error, _reason} = error, _agent, _signal, _plugin_inputs, _specs), do: error

  defp run_pipeline(
         {:ok, state, directives},
         state_before,
         agent_id,
         agent_module,
         signal,
         plugin_inputs,
         specs
       ) do
    with :ok <- protect_owned_state(state, state_before, specs),
         {:ok, directives} <- validate_directives(directives, specs),
         {:ok, state} <-
           reduce_owned_state(
             state,
             state_before,
             agent_id,
             agent_module,
             signal,
             plugin_inputs,
             directives,
             specs
           ) do
      {:ok, state, directives}
    end
  end

  defp protect_owned_state(state, original_state, specs) do
    changed =
      for %{state_key: key} <- specs,
          not is_nil(key),
          Map.fetch(state, key) !== Map.fetch(original_state, key),
          do: key

    if changed == [] do
      :ok
    else
      {:error,
       PluginError.execution(
         "Agent executable changed Plugin-owned state",
         :core,
         __MODULE__,
         %{keys: changed, code: :plugin_state_owner_violation}
       )}
    end
  end

  defp validate_directives(directives, specs) do
    Enum.reduce_while(directives, {:ok, []}, fn
      %{__struct__: _module} = directive, {:ok, acc} ->
        case validate_directive(directive, specs) do
          {:ok, validated} -> {:cont, {:ok, [validated | acc]}}
          {:error, _reason} = error -> {:halt, error}
        end

      directive, _acc ->
        {:halt,
         {:error,
          Error.validation_error("Agent executable returned an invalid Directive",
            details: %{
              code: :agent_invalid_callback_result,
              callback: :execute,
              directive: directive
            }
          )}}
    end)
    |> case do
      {:ok, validated} -> {:ok, Enum.reverse(validated)}
      error -> error
    end
  end

  defp validate_directive(directive, specs) do
    if Jido.Agent.Directive.built_in?(directive) do
      Jido.Agent.Directive.validate(directive)
    else
      case Plugin.directive_owner(specs, directive) do
        %Spec{legacy?: true} = spec ->
          Plugin.validate_legacy_directive(spec, directive)

        %Spec{} ->
          Jido.Agent.Directive.validate(directive)

        nil ->
          {:error,
           Error.validation_error("Agent Directive has no owner",
             kind: :config,
             details: %{directive: directive}
           )}
      end
    end
  end

  defp reduce_owned_state(
         state,
         state_before,
         agent_id,
         agent_module,
         signal,
         plugin_inputs,
         directives,
         specs
       ) do
    Enum.reduce_while(specs, {:ok, state}, fn spec, {:ok, current_state} ->
      case reduce_one(
             spec,
             current_state,
             state_before,
             agent_id,
             agent_module,
             signal,
             plugin_inputs,
             directives
           ) do
        {:ok, updated} -> {:cont, {:ok, updated}}
        {:error, _reason} = error -> {:halt, error}
      end
    end)
  end

  defp reduce_one(
         %Spec{state_key: nil},
         state,
         _state_before,
         _agent_id,
         _agent_module,
         _signal,
         _inputs,
         _directives
       ),
       do: {:ok, state}

  defp reduce_one(
         %Spec{legacy?: true} = spec,
         state,
         _state_before,
         _agent_id,
         _agent_module,
         _signal,
         _inputs,
         directives
       ) do
    if function_exported?(spec.module, :update_state, 3) do
      owned_directives = owned_directives(directives, spec)

      PluginError.safe_apply(
        spec.package,
        spec.module,
        :update_state,
        [Map.get(state, spec.state_key), owned_directives, spec.options],
        "Agent Plugin update_state/3 failed"
      )
      |> validate_reduction(spec, state, :update_state)
    else
      {:ok, state}
    end
  end

  defp reduce_one(
         %Spec{} = spec,
         state,
         state_before,
         agent_id,
         agent_module,
         signal,
         inputs,
         directives
       ) do
    if function_exported?(spec.module, :reduce, 2) do
      package_input = Map.get(inputs, spec.package, %Input{})

      reduction = %Reduction{
        plugin: spec.package,
        agent_id: agent_id,
        agent_module: agent_module,
        signal: signal,
        state_before: state_before,
        state: state,
        plugin_state: Map.get(state, spec.state_key),
        prepared_input: package_input.prepared,
        directives: directives
      }

      PluginError.safe_apply(
        spec.package,
        spec.module,
        :reduce,
        [reduction, spec.options],
        "Agent Plugin reduction failed"
      )
      |> validate_reduction(spec, state, :reduce)
    else
      {:ok, state}
    end
  end

  defp validate_reduction({:ok, value}, spec, state, _callback) do
    case Zoi.parse(spec.state_schema, value) do
      {:ok, value} ->
        with :ok <- portable(value, spec) do
          {:ok, Map.put(state, spec.state_key, value)}
        end

      {:error, issues} ->
        PluginError.invalid_callback(
          "Plugin-owned Agent state field is invalid",
          spec.package,
          spec.module,
          %{issues: issues}
        )
    end
  end

  defp validate_reduction({:error, _reason} = error, _spec, _state, _callback), do: error

  defp validate_reduction(result, spec, _state, callback) do
    PluginError.invalid_callback(
      "Agent Plugin #{callback_label(callback)} returned an invalid result",
      spec.package,
      spec.module,
      %{result: result}
    )
  end

  defp callback_label(:reduce), do: "reduce/2"
  defp callback_label(:update_state), do: "update_state/3"

  defp owned_directives(directives, spec) do
    Enum.filter(directives, &(&1.__struct__ in spec.directive_modules))
  end

  defp portable(value, spec) do
    case Jido.PortableTerm.validate(value, [:plugin_state, spec.package]) do
      :ok ->
        :ok

      {:error, path} ->
        PluginError.invalid_callback(
          "Agent Plugin returned a non-portable value",
          spec.package,
          spec.module,
          %{code: :non_portable_term, path: path}
        )
    end
  end
end

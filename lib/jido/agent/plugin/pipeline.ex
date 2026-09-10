defmodule Jido.Agent.Plugin.Pipeline do
  @moduledoc false

  alias Jido.Agent.Plugin
  alias Jido.Agent.Plugin.Spec
  alias Jido.Error
  alias Jido.Plugin.Error, as: PluginError

  @type result :: {:ok, map(), [struct()]} | {:error, term()}

  @doc false
  @spec run(result(), map(), [Spec.t()]) :: result()
  def run({:ok, state, directives}, original_state, specs)
      when is_map(state) and is_map(original_state) and is_list(directives) and is_list(specs) do
    with :ok <- protect_owned_state(state, original_state, specs),
         {:ok, directives} <- validate_directives(directives, specs),
         {:ok, state} <- update_owned_state(state, directives, specs) do
      {:ok, state, directives}
    end
  end

  def run({:error, _reason} = error, _original_state, _specs), do: error

  defp protect_owned_state(state, original_state, specs) do
    changed =
      specs
      |> Enum.map(& &1.state_key)
      |> Enum.reject(&is_nil/1)
      |> Enum.filter(&(Map.fetch(state, &1) !== Map.fetch(original_state, &1)))

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
    cond do
      Jido.Agent.Directive.built_in?(directive) ->
        Jido.Agent.Directive.validate(directive)

      spec = Plugin.directive_owner(specs, directive) ->
        Plugin.validate_directive(spec, directive)

      true ->
        {:error,
         Error.validation_error("Agent Directive has no owner",
           kind: :config,
           details: %{directive: directive}
         )}
    end
  end

  defp update_owned_state(state, directives, specs) do
    Enum.reduce_while(specs, {:ok, state}, fn spec, {:ok, current_state} ->
      case update_one(spec, current_state, directives) do
        {:ok, updated} -> {:cont, {:ok, updated}}
        {:error, _reason} = error -> {:halt, error}
      end
    end)
  end

  defp update_one(%Spec{state_key: nil}, state, _directives), do: {:ok, state}

  defp update_one(%Spec{} = spec, state, directives) do
    if function_exported?(spec.module, :update_state, 3) do
      owned_directives =
        Enum.filter(directives, fn directive ->
          directive.__struct__ in spec.directive_modules
        end)

      PluginError.safe_apply(
        spec.package,
        spec.module,
        :update_state,
        [Map.get(state, spec.state_key), owned_directives, spec.options],
        "Agent Plugin update_state/3 failed"
      )
      |> validate_update(spec, state)
    else
      {:ok, state}
    end
  end

  defp validate_update({:ok, value}, spec, state) do
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

  defp validate_update({:error, _reason} = error, _spec, _state), do: error

  defp validate_update(result, spec, _state) do
    PluginError.invalid_callback(
      "Agent Plugin update_state/3 returned an invalid result",
      spec.package,
      spec.module,
      %{result: result}
    )
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

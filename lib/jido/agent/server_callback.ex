defmodule Jido.Agent.Server.Callback do
  @moduledoc false

  use ExDbug, enabled: false
  alias Jido.Agent.Server.State, as: ServerState
  alias Jido.Signal
  alias Jido.Signal.Router
  require OK

  @doc """
  Calls the mount callback on the agent if it exists.

  The mount callback is called when the agent server starts up and allows the agent
  to perform any necessary initialization.

  ## Parameters
    - state: The current server state containing the agent

  ## Returns
    - `{:ok, state}` - Mount successful with possibly modified state
    - `{:error, reason}` - Mount failed with reason
  """
  @spec mount(state :: ServerState.t()) :: {:ok, ServerState.t()} | {:error, term()}
  def mount(%ServerState{agent: agent} = state) do
    dbug("Mounting agent", agent: agent)
    mod = agent.__struct__

    if function_exported?(mod, :mount, 2) do
      case mod.mount(state, []) do
        {:ok, new_state} -> {:ok, new_state}
        {:error, _} = err -> err
        other -> {:error, {:invalid_return, other}}
      end
    else
      {:ok, state}
    end
  end

  @doc """
  Calls the code_change callback on the agent if it exists.

  The code_change callback is called when the agent's code is updated during a hot code upgrade.

  ## Parameters
    - state: The current server state containing the agent
    - old_vsn: The version being upgraded from
    - extra: Additional data passed to the upgrade

  ## Returns
    - `{:ok, state}` - Code change successful with possibly modified state
    - `{:error, reason}` - Code change failed with reason
  """
  @spec code_change(state :: ServerState.t(), old_vsn :: term(), extra :: term()) ::
          {:ok, ServerState.t()} | {:error, term()}
  def code_change(%ServerState{agent: agent} = state, old_vsn, extra) do
    dbug("Code change", agent: agent, old_vsn: old_vsn, extra: extra)
    mod = agent.__struct__

    if function_exported?(mod, :code_change, 3) do
      case mod.code_change(state, old_vsn, extra) do
        {:ok, new_state} -> {:ok, new_state}
        {:error, _} = err -> err
        other -> {:error, {:invalid_return, other}}
      end
    else
      {:ok, state}
    end
  end

  @doc """
  Calls the shutdown callback on the agent if it exists.

  The shutdown callback is called when the agent server is stopping and allows the agent
  to perform any necessary cleanup.

  ## Parameters
    - state: The current server state containing the agent
    - reason: The reason for shutdown

  ## Returns
    - `{:ok, state}` - Shutdown successful with possibly modified state
    - `{:error, reason}` - Shutdown failed with reason
  """
  @spec shutdown(state :: ServerState.t(), reason :: term()) ::
          {:ok, ServerState.t()} | {:error, term()}
  def shutdown(%ServerState{agent: agent} = state, reason) do
    dbug("Shutting down agent", agent: agent, reason: reason)
    mod = agent.__struct__

    if function_exported?(mod, :shutdown, 2) do
      case mod.shutdown(state, reason) do
        {:ok, new_state} -> {:ok, new_state}
        {:error, _} = err -> err
        other -> {:error, {:invalid_return, other}}
      end
    else
      {:ok, state}
    end
  end

  @doc """
  Calls the handle_signal callback on the agent and all matching skills.

  The signal is first processed by the agent, then by any skills whose patterns
  match the signal type. Each handler can modify the signal before passing it
  to the next handler. If any handler fails, the original signal is returned.

  ## Parameters
    - state: The current server state containing the agent and skills
    - signal: The signal to handle, or {:ok, signal} tuple

  ## Returns
    - `{:ok, signal}` - Signal successfully handled with possibly modified signal
    - `{:error, reason}` - Signal handling failed with reason
  """
  @spec handle_signal(state :: ServerState.t(), signal :: Signal.t() | {:ok, Signal.t()}) ::
          {:ok, Signal.t()} | {:error, term()}
  def handle_signal(state, {:ok, signal}), do: handle_signal(state, signal)

  def handle_signal(%ServerState{skills: skills} = state, %Signal{} = signal) do
    dbug("Starting signal pipeline", signal: signal)

    # First try to handle with the agent
    case safe_agent_handle_signal(state, signal) do
      {:ok, handled_signal} ->
        dbug("Agent handled signal", handled_signal: handled_signal)

        # Then try to handle with matching skills
        matching_skills = find_matching_skills(skills, signal)
        dbug("Found matching skills", count: length(matching_skills))

        # Process through each matching skill
        final_signal =
          Enum.reduce(matching_skills, handled_signal, fn skill, acc_signal ->
            case safe_skill_handle_signal(state, skill, acc_signal) do
              {:ok, new_signal} ->
                dbug("Skill processed signal", skill: skill)
                new_signal

              {:error, _reason} ->
                dbug("Skill failed to process signal, continuing with previous signal",
                  skill: skill
                )

                acc_signal
            end
          end)

        {:ok, final_signal}

      {:error, _reason} ->
        dbug("Agent failed to handle signal, returning original signal")
        {:ok, signal}
    end
  end

  # Safely calls handle_signal on a module, returning the original signal if it fails
  defp safe_agent_handle_signal(state, signal) do
    try do
      agent = state.agent

      case agent.__struct__.handle_signal(signal, agent) do
        {:ok, new_signal} -> {:ok, new_signal}
        {:error, reason} -> {:error, reason}
        other -> {:error, {:invalid_return, other}}
      end
    rescue
      e ->
        # dbug("Error in handle_signal", agent: agent, error: e)
        {:error, e}
    catch
      kind, value ->
        # dbug("Caught error in handle_signal", agent: agent, kind: kind, value: value)
        {:error, {kind, value}}
    end
  end

  # Safely calls handle_signal on a module, returning the original signal if it fails
  defp safe_skill_handle_signal(state, skill, signal) do
    try do
      opts_key = skill.opts_key()
      opts = Keyword.get(state.opts, opts_key, [])

      case skill.handle_signal(signal, opts) do
        {:ok, new_signal} -> {:ok, new_signal}
        {:error, reason} -> {:error, reason}
        other -> {:error, {:invalid_return, other}}
      end
    rescue
      e ->
        # dbug("Error in handle_signal", skill: skill, error: e)
        {:error, e}
    catch
      kind, value ->
        # dbug("Caught error in handle_signal", skill: skill, kind: kind, value: value)
        {:error, {kind, value}}
    end
  end

  @doc """
  Calls the transform_result callback on the agent and all matching skills.

  The result is first processed by the agent, then by any skills whose patterns
  match the signal type. Each handler can modify the result before passing it
  to the next handler. If any handler fails, the original result is returned.

  ## Parameters
    - state: The current server state containing the agent and skills
    - signal: The signal that produced the result
    - result: The result to process

  ## Returns
    - `{:ok, result}` - Result successfully processed with possibly modified result
    - `{:error, reason}` - Result processing failed with reason
  """
  @spec transform_result(ServerState.t(), Signal.t() | {:ok, Signal.t()} | nil, term()) ::
          {:ok, term()}
  def transform_result(state, {:ok, signal}, result) do
    transform_result(state, signal, result)
  end

  @dialyzer {:nowarn_function, transform_result: 3}
  def transform_result(
        %ServerState{agent: agent, skills: skills} = _state,
        %Signal{} = signal,
        result
      ) do
    dbug("Starting result transformation pipeline", signal: signal, result: result)

    # First try to transform with the agent
    case safe_transform_result(agent.__struct__, signal, result, agent) do
      {:ok, transformed_result} ->
        dbug("Agent transformed result", transformed_result: transformed_result)

        # Then try to transform with matching skills
        matching_skills = find_matching_skills(skills, signal)
        dbug("Found matching skills", count: length(matching_skills))

        # Process through each matching skill
        final_result =
          Enum.reduce(matching_skills, transformed_result, fn skill, acc_result ->
            case safe_transform_result(skill, signal, acc_result, skill) do
              {:ok, new_result} ->
                dbug("Skill transformed result", skill: skill)
                new_result

              {:error, _reason} ->
                dbug("Skill failed to transform result, continuing with previous result",
                  skill: skill
                )

                acc_result
            end
          end)

        {:ok, final_result}

      {:error, _reason} ->
        dbug("Agent failed to transform result, returning original result")
        {:ok, result}
    end
  end

  def transform_result(%ServerState{} = _state, nil, result) do
    dbug("Processing result with no signal", result: result)
    {:ok, result}
  end

  # Safely calls transform_result on a module, returning the original result if it fails
  @spec safe_transform_result(module(), Signal.t(), term(), Jido.Agent.t() | Jido.Skill.t()) ::
          {:ok, term()} | {:error, term()}
  defp safe_transform_result(module, signal, result, struct) do
    if function_exported?(module, :transform_result, 3) do
      try do
        case module.transform_result(signal, result, struct) do
          {:ok, new_result} -> {:ok, new_result}
          {:error, reason} -> {:error, reason}
          other -> {:error, {:invalid_return, other}}
        end
      rescue
        e ->
          dbug("Error in transform_result", module: module, error: e)
          {:error, e}
      catch
        kind, value ->
          dbug("Caught error in transform_result", module: module, kind: kind, value: value)
          {:error, {kind, value}}
      end
    else
      {:ok, result}
    end
  end

  # Finds skills that match a signal's type based on their input/output patterns.
  #
  # Parameters:
  #   - skills: List of skills to check
  #   - signal: Signal to match against
  #
  # Returns:
  #   List of matching skills
  @spec find_matching_skills(skills :: list(Jido.Skill.t()) | nil, signal :: Signal.t() | nil) ::
          list(Jido.Skill.t())
  defp find_matching_skills(nil, _signal), do: []

  defp find_matching_skills(skills, %Signal{} = signal) when is_list(skills) do
    matches =
      Enum.filter(skills, fn skill ->
        try do
          case skill do
            nil ->
              false

            skill ->
              case skill.signal_patterns() do
                nil ->
                  false

                patterns when is_list(patterns) ->
                  Enum.any?(patterns, fn pattern ->
                    case pattern do
                      pattern when is_binary(pattern) ->
                        matches = Router.matches?(signal.type, pattern)
                        dbug("Pattern match result", pattern: pattern, matches: matches)
                        matches

                      _invalid ->
                        false
                    end
                  end)

                _invalid ->
                  dbug("Invalid patterns format - must be list")
                  false
              end
          end
        rescue
          _ ->
            dbug("Error matching skill patterns")
            false
        end
      end)

    dbug("Found matching skills", matches: matches, count: length(matches))
    matches
  end

  defp find_matching_skills(_skills, _signal), do: []
end

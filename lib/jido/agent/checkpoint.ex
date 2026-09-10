defmodule Jido.Agent.Checkpoint do
  @moduledoc false

  alias Jido.Agent
  alias Jido.Error
  alias Jido.PortableTerm

  @version 2
  @default_keys [:version, :kind, :agent_module, :vsn, :id, :state]
  @embedded_keys @default_keys ++ [:definition]
  @custom_keys [:version, :kind, :agent_module, :vsn, :payload]

  @doc false
  @spec checkpoint(Agent.instance(), map()) :: {:ok, map()} | {:error, term()}
  def checkpoint(%Agent{} = agent, context) when is_map(context) and not is_struct(context) do
    with {:ok, agent} <- Agent.validate_instance(agent),
         :ok <- current_vsn(agent.module, agent.vsn) do
      if callback?(agent.module, :checkpoint) do
        with {:ok, payload} <- invoke(agent.module, :checkpoint, [agent, context]),
             :ok <- plain_map(payload, :checkpoint),
             :ok <- portable(payload, [:checkpoint, :payload]) do
          {:ok,
           %{
             version: @version,
             kind: :agent_custom,
             agent_module: agent.module,
             vsn: agent.vsn,
             payload: payload
           }}
        end
      else
        default_checkpoint(agent, context)
      end
    end
  end

  def checkpoint(agent, context) do
    invalid("Agent checkpoint requires an Agent instance and a context map", %{
      agent: agent,
      context: context
    })
  end

  @doc false
  @spec restore(module(), map(), map()) :: {:ok, Agent.instance()} | {:error, term()}
  def restore(module, checkpoint, context)
      when is_atom(module) and is_map(checkpoint) and not is_struct(checkpoint) and
             is_map(context) and not is_struct(context) do
    case checkpoint do
      %{version: @version, kind: :agent_custom} -> restore_custom(module, checkpoint, context)
      %{version: @version, kind: :agent} -> default_restore(module, checkpoint, context)
      _other -> invalid_checkpoint(checkpoint)
    end
  end

  def restore(module, checkpoint, context) do
    invalid("Agent restore requires a module, checkpoint map, and context map", %{
      module: module,
      checkpoint: checkpoint,
      context: context
    })
  end

  @doc false
  @spec default_checkpoint(Agent.instance(), map()) :: {:ok, map()} | {:error, term()}
  def default_checkpoint(%Agent{} = agent, _context) do
    definition = Agent.definition(agent)

    with :ok <- checkpoint_definition(agent, definition) do
      checkpoint = %{
        version: @version,
        kind: :agent,
        agent_module: agent.module,
        vsn: agent.vsn,
        id: agent.id,
        state: agent.state
      }

      checkpoint =
        if embedded_definition?(agent),
          do: Map.put(checkpoint, :definition, definition),
          else: checkpoint

      with :ok <- portable(checkpoint, :checkpoint), do: {:ok, checkpoint}
    end
  end

  def default_checkpoint(agent, _context),
    do: invalid("Default checkpoint requires an Agent instance", %{agent: agent})

  @doc false
  @spec default_restore(module(), map(), map()) ::
          {:ok, Agent.instance()} | {:error, term()}
  def default_restore(module, checkpoint, _context)
      when is_atom(module) and is_map(checkpoint) and not is_struct(checkpoint) do
    with :ok <- portable(checkpoint, :checkpoint) do
      cond do
        exact_keys?(checkpoint, @default_keys) -> restore_generated(module, checkpoint)
        exact_keys?(checkpoint, @embedded_keys) -> restore_embedded(module, checkpoint)
        true -> invalid_checkpoint(checkpoint)
      end
    end
  end

  def default_restore(module, checkpoint, _context),
    do: invalid_checkpoint(%{module: module, checkpoint: checkpoint})

  defp restore_generated(module, checkpoint) do
    with :ok <- default_header(module, checkpoint, :generated),
         {:ok, definition} <- current_definition(module),
         :ok <- same_vsn(checkpoint.vsn, definition.vsn),
         {:ok, agent} <- Agent.instantiate(definition, id: checkpoint.id, state: checkpoint.state) do
      {:ok, agent}
    end
  end

  defp restore_embedded(module, checkpoint) do
    with :ok <- default_header(module, checkpoint, :embedded),
         {:ok, definition} <- Agent.validate_definition(checkpoint.definition),
         :ok <- embedded_header(module, checkpoint, definition),
         {:ok, agent} <-
           Agent.instantiate(definition, id: checkpoint.id, state: checkpoint.state) do
      {:ok, agent}
    end
  end

  defp restore_custom(module, checkpoint, context) do
    with true <- exact_keys?(checkpoint, @custom_keys),
         :ok <- custom_header(module, checkpoint),
         :ok <- plain_map(checkpoint.payload, :restore),
         :ok <- portable(checkpoint.payload, [:checkpoint, :payload]),
         true <- callback?(module, :restore),
         {:ok, agent} <- invoke(module, :restore, [checkpoint.payload, context]),
         {:ok, agent} <- Agent.validate_instance(agent),
         :ok <- restored_identity(module, checkpoint.vsn, agent) do
      {:ok, agent}
    else
      false -> invalid_checkpoint(checkpoint)
      {:error, _reason} = error -> error
      result -> invalid_callback(:restore, result)
    end
  end

  defp default_header(module, checkpoint, format) do
    valid_vsn? =
      case format do
        :generated -> is_integer(checkpoint.vsn) and checkpoint.vsn > 0
        :embedded -> is_nil(checkpoint.vsn) or (is_integer(checkpoint.vsn) and checkpoint.vsn > 0)
      end

    if checkpoint.version == @version and checkpoint.kind == :agent and
         checkpoint.agent_module == module and valid_vsn? and
         is_binary(checkpoint.id) and byte_size(checkpoint.id) > 0 and
         is_map(checkpoint.state) and not is_struct(checkpoint.state) do
      :ok
    else
      invalid_checkpoint(checkpoint)
    end
  end

  defp embedded_header(module, checkpoint, definition) do
    if definition.module == module and definition.vsn == checkpoint.vsn,
      do: :ok,
      else: definition_mismatch(module, checkpoint.vsn)
  end

  defp custom_header(module, checkpoint) do
    valid_vsn? = is_nil(checkpoint.vsn) or (is_integer(checkpoint.vsn) and checkpoint.vsn > 0)

    with true <- checkpoint.version == @version,
         true <- checkpoint.kind == :agent_custom,
         true <- checkpoint.agent_module == module,
         true <- valid_vsn?,
         :ok <- current_vsn(module, checkpoint.vsn) do
      :ok
    else
      false -> invalid_checkpoint(checkpoint)
      {:error, _reason} = error -> error
    end
  end

  defp checkpoint_definition(agent, definition) do
    if embedded_definition?(agent) do
      :ok
    else
      with {:ok, current} <- current_definition(agent.module) do
        if current == definition,
          do: :ok,
          else: definition_mismatch(agent.module, agent.vsn)
      end
    end
  end

  defp embedded_definition?(%Agent{module: Agent}), do: true
  defp embedded_definition?(%Agent{vsn: nil}), do: true
  defp embedded_definition?(%Agent{module: module}), do: not generated?(module)

  defp current_definition(module) do
    if generated?(module) do
      case Agent.validate_definition(module.definition()) do
        {:ok, definition} -> {:ok, definition}
        {:error, _reason} -> definition_mismatch(module, nil)
      end
    else
      invalid_checkpoint(%{agent_module: module})
    end
  end

  defp current_vsn(_module, nil), do: :ok

  defp current_vsn(module, vsn) do
    if generated?(module) do
      same_vsn(vsn, module.vsn())
    else
      :ok
    end
  end

  defp same_vsn(vsn, vsn), do: :ok
  defp same_vsn(_checkpoint_vsn, current_vsn), do: definition_mismatch(nil, current_vsn)

  defp restored_identity(module, vsn, %Agent{} = agent) do
    if agent.module == module and agent.vsn == vsn do
      :ok
    else
      if agent.module != module,
        do:
          invalid("Restored Agent module does not match", %{
            expected: module,
            actual: agent.module
          }),
        else: definition_mismatch(module, vsn)
    end
  end

  defp invoke(module, callback, args) do
    case safe_apply(module, callback, args) do
      {:ok, {:ok, value}} -> {:ok, value}
      {:ok, {:error, reason}} -> {:error, reason}
      {:ok, result} -> invalid_callback(callback, result)
      {:error, kind, reason} -> callback_failed(module, callback, kind, reason)
    end
  end

  defp safe_apply(module, callback, args) do
    {:ok, apply(module, callback, args)}
  rescue
    error -> {:error, :error, error}
  catch
    kind, reason -> {:error, kind, reason}
  end

  defp plain_map(value, _callback) when is_map(value) and not is_struct(value), do: :ok
  defp plain_map(value, callback), do: invalid_callback(callback, {:ok, value})

  defp portable(value, root) do
    case PortableTerm.validate(value, root) do
      :ok ->
        :ok

      {:error, path} ->
        {:error,
         Error.validation_error("Agent checkpoint contains a non-portable term",
           details: %{code: :non_portable_term, path: path}
         )}
    end
  end

  defp callback?(module, callback),
    do: module != Agent and function_exported?(module, callback, 2)

  defp generated?(module),
    do:
      module != Agent and function_exported?(module, :definition, 0) and
        function_exported?(module, :vsn, 0)

  defp exact_keys?(map, keys), do: Enum.sort(Map.keys(map)) == Enum.sort(keys)

  defp invalid_checkpoint(checkpoint),
    do: invalid("Invalid Agent checkpoint", %{code: :invalid_checkpoint, checkpoint: checkpoint})

  defp definition_mismatch(module, vsn),
    do:
      invalid(
        "Agent definition does not match its checkpoint",
        %{code: :definition_mismatch, module: module, vsn: vsn}
      )

  defp invalid_callback(callback, result),
    do:
      invalid(
        "Agent callback returned an invalid result",
        %{code: :agent_invalid_callback_result, callback: callback, result: result}
      )

  defp callback_failed(module, callback, kind, reason) do
    {:error,
     Error.execution_error("Agent callback failed",
       details: %{
         code: :agent_callback_failed,
         module: module,
         callback: callback,
         kind: kind,
         reason: reason
       }
     )}
  end

  defp invalid(message, details),
    do: {:error, Error.validation_error(message, details: details)}
end

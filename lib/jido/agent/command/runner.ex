defmodule Jido.Agent.Command.Runner do
  @moduledoc false

  alias Jido.Agent
  alias Jido.Agent.{Command, Turn}
  alias Jido.Error
  alias Jido.Plugin
  alias Jido.Signal
  alias Jido.Signal.Router

  @reserved_context_keys [:agent_id, :agent_state, :signal]

  defmodule Prepared do
    @moduledoc false

    @enforce_keys [:agent, :signal, :turn, :context, :exec_opts, :plugin_specs]
    defstruct @enforce_keys

    @type t :: %__MODULE__{
            agent: Jido.Agent.t(),
            signal: Jido.Signal.t(),
            turn: Jido.Agent.Turn.t(),
            context: map(),
            exec_opts: keyword(),
            plugin_specs: [Jido.Plugin.Spec.t()]
          }
  end

  @doc false
  @spec run(Agent.t(), Signal.t(), keyword()) ::
          {:ok, Agent.t(), [struct()]} | {:error, term()}
  def run(%Agent{} = agent, %Signal{} = signal, opts) when is_list(opts) do
    with {:ok, prepared} <- prepare(agent, signal, opts),
         result <-
           Jido.Exec.run(
             prepared.turn.executable,
             prepared.turn.input,
             prepared.context,
             prepared.exec_opts
           ) do
      finish(prepared, result)
    end
  rescue
    error -> {:error, error}
  catch
    kind, reason -> {:error, {kind, reason}}
  end

  @doc false
  @spec prepare(Agent.t(), Signal.t(), keyword()) ::
          {:ok, Prepared.t()} | {:error, term()}
  def prepare(%Agent{} = agent, %Signal{} = signal, opts) when is_list(opts) do
    do_prepare(agent, signal, opts, :normalize)
  end

  @doc false
  @spec prepare(Agent.t(), Signal.t(), keyword(), [Jido.Plugin.Spec.t()]) ::
          {:ok, Prepared.t()} | {:error, term()}
  def prepare(%Agent{} = agent, %Signal{} = signal, opts, plugin_specs)
      when is_list(opts) and is_list(plugin_specs) do
    do_prepare(agent, signal, opts, {:prepared, plugin_specs})
  end

  defp do_prepare(%Agent{} = agent, %Signal{} = signal, opts, plugin_source) do
    {caller_context, exec_opts} = Keyword.pop(opts, :context, %{})

    with {:ok, caller_context} <- Command.normalize_context(caller_context),
         {:ok, agent} <- Agent.validate_instance(agent),
         {:ok, command} <- Command.new(agent, signal, caller_context),
         {:ok, command, plugin_specs} <-
           prepare_plugins(command, agent.plugins, plugin_source),
         :ok <- ensure_original_agent(command.agent, agent),
         :ok <- reject_reserved_context(command.context, :command),
         {:ok, turn} <- prepare_run_turn(agent, command.signal) do
      context =
        Map.merge(command.context, %{
          agent_id: agent.id,
          agent_state: agent.state,
          signal: command.signal
        })

      {:ok,
       %Prepared{
         agent: agent,
         signal: command.signal,
         turn: turn,
         context: context,
         exec_opts: exec_opts,
         plugin_specs: plugin_specs
       }}
    else
      {:error, error} -> {:error, normalize_routing_error(error, signal)}
    end
  end

  @doc false
  @spec finish_for_server(Prepared.t(), term()) ::
          {:ok, Agent.t(), [struct()]} | {:error, term()}
  def finish_for_server(%Prepared{} = prepared, result) do
    finish(prepared, result)
  rescue
    error -> finalization_error(:error, error)
  catch
    kind, reason -> finalization_error(kind, reason)
  end

  @doc false
  @spec prepare_default_turn(Signal.t(), Agent.t()) :: Agent.handle_result()
  def prepare_default_turn(%Signal{} = signal, %Agent{} = agent) do
    with {:ok, router} <- Router.new(agent.routes),
         {:ok, [target]} <- route_one(router, signal),
         {:ok, executable, input} <- prepare_target(target, signal),
         {:ok, turn} <- Turn.new(executable, input) do
      {:ok, turn}
    else
      {:error, error} -> {:error, normalize_routing_error(error, signal)}
    end
  end

  defp finish(%Prepared{} = prepared, result) do
    with {:ok, output, directives} <- normalize_exec_result(result),
         {:ok, output, directives} <-
           Plugin.protect_state(
             {:ok, output, directives},
             prepared.agent.state,
             prepared.plugin_specs
           ),
         {:ok, directives} <- validate_directives(directives, prepared.plugin_specs),
         {:ok, output, directives} <-
           Plugin.update_state({:ok, output, directives}, prepared.plugin_specs),
         {:ok, agent} <- Agent.transition(prepared.agent, output) do
      {:ok, agent, directives}
    end
  end

  defp normalize_exec_result({:ok, output}) when is_map(output) and not is_struct(output),
    do: {:ok, output, []}

  defp normalize_exec_result({:ok, output, directives})
       when is_map(output) and not is_struct(output),
       do: {:ok, output, List.wrap(directives)}

  defp normalize_exec_result({:ok, output}), do: invalid_state_output(output)
  defp normalize_exec_result({:ok, output, _directives}), do: invalid_state_output(output)

  defp normalize_exec_result({:error, reason}), do: {:error, reason}
  defp normalize_exec_result({:error, reason, _extras}), do: {:error, reason}

  defp normalize_exec_result(result) do
    {:error,
     Error.execution_error("Agent executable returned an invalid result",
       details: %{result: result}
     )}
  end

  defp ensure_original_agent(agent, agent), do: :ok

  defp ensure_original_agent(replacement, agent) do
    {:error,
     Error.execution_error("Agent Plugin cannot replace the Agent",
       details: %{expected_agent_id: agent.id, replacement: replacement}
     )}
  end

  defp reject_reserved_context(context, source) do
    if Enum.any?(@reserved_context_keys, &Map.has_key?(context, &1)) do
      keys = Map.keys(context) |> Enum.filter(&(&1 in @reserved_context_keys))

      {:error,
       Error.validation_error("Agent #{source} context contains reserved keys",
         details: %{keys: keys}
       )}
    else
      :ok
    end
  end

  defp route_one(router, signal) do
    case Router.route(router, signal) do
      {:ok, [_target] = targets} ->
        {:ok, targets}

      {:ok, targets} ->
        {:error,
         Error.routing_error("Agent Signal must resolve to exactly one executable",
           target: signal.type,
           details: %{count: length(targets), targets: targets}
         )}

      {:error, error} ->
        {:error, error}
    end
  end

  defp normalize_routing_error(%Jido.Signal.Error.RoutingError{} = error, signal) do
    Error.routing_error(error.message,
      target: error.target || signal.type,
      details: Map.put(error.details || %{}, :cause, error)
    )
  end

  defp normalize_routing_error(error, _signal), do: error

  defp prepare_target({executable, defaults}, %Signal{data: data})
       when is_map(defaults) and is_map(data) do
    {:ok, executable, Map.merge(defaults, data)}
  end

  defp prepare_target(executable, %Signal{data: data}) when is_map(data) do
    {:ok, executable, data}
  end

  defp prepare_target(_executable, %Signal{} = signal) do
    {:error,
     Error.validation_error("Agent Signal data must be a map",
       field: :data,
       details: %{signal_id: signal.id, data: signal.data}
     )}
  end

  defp prepare_run_turn(agent, signal) do
    case agent.module.handle_signal(signal, agent) do
      {:ok, %Turn{} = turn} -> Turn.validate(turn)
      {:error, reason} -> {:error, reason}
      result -> {:error, invalid_callback_result(result, agent.module)}
    end
  end

  defp validate_directives(directives, plugins) when is_list(directives) do
    Enum.reduce_while(directives, {:ok, []}, fn
      %{__struct__: _module} = directive, {:ok, acc} ->
        case validate_directive(directive, plugins) do
          {:ok, directive} -> {:cont, {:ok, [directive | acc]}}
          {:error, reason} -> {:halt, {:error, reason}}
        end

      directive, _acc ->
        {:halt,
         {:error,
          Error.validation_error("Agent executable returned an invalid Directive",
            details: %{directive: directive}
          )}}
    end)
    |> case do
      {:ok, directives} -> {:ok, Enum.reverse(directives)}
      error -> error
    end
  end

  defp validate_directive(directive, plugins) do
    cond do
      Jido.Agent.Directive.built_in?(directive) ->
        Jido.Agent.Directive.validate(directive)

      plugin = Plugin.directive_owner(plugins, directive) ->
        Plugin.validate_directive(plugin, directive)

      true ->
        invalid("Agent Directive has no owner", %{directive: directive})
    end
  end

  defp prepare_plugins(command, declarations, :normalize) do
    Plugin.prepare(command, declarations)
  end

  defp prepare_plugins(command, _declarations, {:prepared, plugin_specs}) do
    Plugin.prepare_specs(command, plugin_specs)
  end

  defp invalid_state_output(output) do
    {:error,
     Error.execution_error("Agent executable output must be a plain state map",
       details: %{output: output}
     )}
  end

  defp finalization_error(kind, reason) do
    {:error,
     Error.execution_error("Agent turn finalization failed",
       details: %{kind: kind, reason: reason}
     )}
  end

  defp invalid_callback_result(result, module) do
    Error.execution_error("Agent handle_signal/2 returned an invalid result",
      details: %{module: module, result: result}
    )
  end

  defp invalid(message, details) do
    {:error, Error.validation_error(message, kind: :config, details: details)}
  end
end

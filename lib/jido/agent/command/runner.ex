defmodule Jido.Agent.Command.Runner do
  @moduledoc false

  alias Jido.Agent
  alias Jido.Agent.{Command, Turn}
  alias Jido.Error
  alias Jido.Plugin
  alias Jido.Signal
  alias Jido.Signal.Router

  @reserved_context_keys [:agent_id, :agent_state, :signal]
  @type stage :: :route | :prepare | :input | :execute | :compose | :validate

  defmodule Prepared do
    @moduledoc false

    @enforce_keys [
      :agent,
      :source_signal,
      :signal,
      :turn,
      :context,
      :exec_opts,
      :plugin_specs
    ]
    defstruct @enforce_keys

    @type t :: %__MODULE__{
            agent: Jido.Agent.t(),
            source_signal: Jido.Signal.t(),
            signal: Jido.Signal.t(),
            turn: Jido.Agent.Turn.t(),
            context: map(),
            exec_opts: keyword(),
            plugin_specs: [Jido.Plugin.Spec.t()]
          }
  end

  defmodule Selection do
    @moduledoc false

    @enforce_keys [:turn, :input_mode]
    defstruct @enforce_keys

    @type t :: %__MODULE__{
            turn: Jido.Agent.Turn.t(),
            input_mode: :fixed | {:route, map()}
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
  end

  @doc false
  @spec prepare(Agent.t(), Signal.t(), keyword()) ::
          {:ok, Prepared.t()} | {:error, term()}
  def prepare(%Agent{} = agent, %Signal{} = signal, opts) when is_list(opts) do
    agent
    |> do_prepare(signal, signal, opts, :normalize)
    |> unstage()
  end

  @doc false
  @spec prepare(Agent.t(), Signal.t(), keyword(), [Jido.Plugin.Spec.t()]) ::
          {:ok, Prepared.t()} | {:error, term()}
  def prepare(%Agent{} = agent, %Signal{} = signal, opts, plugin_specs)
      when is_list(opts) and is_list(plugin_specs) do
    agent
    |> do_prepare(signal, signal, opts, {:prepared, plugin_specs})
    |> unstage()
  end

  @doc false
  @spec prepare_for_server(
          Agent.t(),
          Signal.t(),
          Signal.t(),
          keyword(),
          [Jido.Plugin.Spec.t()]
        ) :: {:ok, Prepared.t()} | {:error, stage(), term()}
  def prepare_for_server(
        %Agent{} = agent,
        %Signal{} = source_signal,
        %Signal{} = effective_signal,
        opts,
        plugin_specs
      )
      when is_list(opts) and is_list(plugin_specs) do
    do_prepare(agent, source_signal, effective_signal, opts, {:prepared, plugin_specs})
  end

  defp do_prepare(
         %Agent{} = agent,
         %Signal{} = source_signal,
         %Signal{} = effective_signal,
         opts,
         plugin_source
       ) do
    {caller_context, exec_opts} = Keyword.pop(opts, :context, %{})

    with {:ok, caller_context} <- at(:input, Command.normalize_context(caller_context)),
         {:ok, agent} <-
           at(
             :input,
             normalize_result_routing_error(Agent.validate_instance(agent), source_signal)
           ),
         {:ok, selection} <-
           at(
             :route,
             normalize_result_routing_error(
               prepare_selection(agent, source_signal),
               source_signal
             )
           ),
         {:ok, command} <- at(:input, Command.new(agent, effective_signal, caller_context)),
         {:ok, command, plugin_specs} <-
           at(:prepare, prepare_plugins(command, agent.plugins, plugin_source)),
         :ok <- at(:prepare, ensure_original_agent(command.agent, agent)),
         :ok <- at(:prepare, reject_reserved_context(command.context, :command)),
         {:ok, turn} <- at(:input, materialize_turn(selection, command.signal)) do
      context =
        Map.merge(command.context, %{
          agent_id: agent.id,
          agent_state: agent.state,
          signal: command.signal
        })

      {:ok,
       %Prepared{
         agent: agent,
         source_signal: source_signal,
         signal: command.signal,
         turn: turn,
         context: context,
         exec_opts: exec_opts,
         plugin_specs: plugin_specs
       }}
    end
  end

  @doc false
  @spec finish_for_server(Prepared.t(), term()) ::
          {:ok, Agent.t(), [struct()]} | {:error, stage(), term()}
  def finish_for_server(%Prepared{} = prepared, result) do
    do_finish(prepared, result)
  end

  @doc false
  @spec prepare_default_turn(Signal.t(), Agent.t()) :: Agent.handle_result()
  def prepare_default_turn(%Signal{} = signal, %Agent{} = agent) do
    with {:ok, selection} <- prepare_default_selection(signal, agent),
         {:ok, turn} <- materialize_turn(selection, signal) do
      {:ok, turn}
    else
      {:error, error} -> {:error, normalize_routing_error(error, signal)}
    end
  end

  defp finish(%Prepared{} = prepared, result) do
    prepared
    |> do_finish(result)
    |> unstage()
  end

  defp do_finish(%Prepared{} = prepared, result) do
    with {:ok, output, directives} <- at(:compose, normalize_exec_result(result)),
         {:ok, output, directives} <-
           at(
             :compose,
             Plugin.protect_state(
               {:ok, output, directives},
               prepared.agent.state,
               prepared.plugin_specs
             )
           ),
         {:ok, directives} <-
           at(:validate, validate_directives(directives, prepared.plugin_specs)),
         {:ok, output, directives} <-
           at(
             :compose,
             Plugin.update_state({:ok, output, directives}, prepared.plugin_specs)
           ),
         {:ok, agent} <- at(:validate, Agent.transition(prepared.agent, output)) do
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
       details: %{code: :agent_invalid_callback_result, callback: :execute, result: result}
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

  defp route_first(router, signal) do
    case Router.route(router, signal) do
      {:ok, [target | _targets]} ->
        {:ok, target}

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

  defp normalize_result_routing_error({:error, error}, signal),
    do: {:error, normalize_routing_error(error, signal)}

  defp normalize_result_routing_error(result, _signal), do: result

  defp prepare_selection(%Agent{module: module} = agent, signal) do
    if default_handle_signal?(module) do
      prepare_default_selection(signal, agent)
    else
      prepare_custom_selection(agent, signal)
    end
  end

  defp prepare_default_selection(signal, agent) do
    with {:ok, router} <- Router.new(agent.routes),
         {:ok, target} <- route_first(router, signal),
         {:ok, executable, defaults} <- select_target(target),
         {:ok, input} <- merge_route_input(defaults, signal),
         {:ok, turn} <- Turn.new(executable, input, signal) do
      {:ok, %Selection{turn: turn, input_mode: {:route, defaults}}}
    end
  end

  defp prepare_custom_selection(agent, signal) do
    case invoke_agent_callback(agent.module, :handle_signal, [signal, agent]) do
      {:ok, %Turn{} = turn} ->
        with {:ok, turn} <- Turn.validate(turn),
             {:ok, turn} <- Turn.bind_source(turn, signal),
             do: {:ok, %Selection{turn: turn, input_mode: :fixed}}

      {:error, reason} ->
        {:error, reason}

      result ->
        {:error, invalid_callback_result(result, agent.module)}
    end
    |> normalize_result_routing_error(signal)
  end

  defp materialize_turn(%Selection{turn: turn, input_mode: :fixed}, _effective_signal),
    do: {:ok, turn}

  defp materialize_turn(
         %Selection{turn: turn, input_mode: {:route, defaults}},
         effective_signal
       ) do
    with {:ok, input} <- merge_route_input(defaults, effective_signal),
         do: Turn.new(turn.executable, input, turn.source_signal)
  end

  defp default_handle_signal?(Agent), do: true

  defp default_handle_signal?(module) do
    function_exported?(module, :__jido_default_handle_signal__?, 0) and
      module.__jido_default_handle_signal__?()
  end

  defp select_target({executable, defaults}) when is_map(defaults),
    do: {:ok, executable, defaults}

  defp select_target(executable), do: {:ok, executable, %{}}

  defp merge_route_input(defaults, %Signal{data: data})
       when is_map(defaults) and is_map(data),
       do: {:ok, Map.merge(defaults, data)}

  defp merge_route_input(_defaults, %Signal{} = signal) do
    {:error,
     Error.validation_error("Agent Signal data must be a map",
       field: :data,
       details: %{signal_id: signal.id, data: signal.data}
     )}
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
            details: %{
              code: :agent_invalid_callback_result,
              callback: :execute,
              directive: directive
            }
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
       details: %{code: :agent_invalid_callback_result, callback: :execute, output: output}
     )}
  end

  defp invalid_callback_result(result, module) do
    Error.execution_error("Agent handle_signal/2 returned an invalid result",
      details: %{
        code: :agent_invalid_callback_result,
        module: module,
        callback: :handle_signal,
        result: result
      }
    )
  end

  defp invoke_agent_callback(module, callback, args) do
    apply(module, callback, args)
  rescue
    error -> agent_callback_error(module, callback, :error, error)
  catch
    kind, reason -> agent_callback_error(module, callback, kind, reason)
  end

  defp agent_callback_error(module, callback, kind, reason) do
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

  defp invalid(message, details) do
    {:error, Error.validation_error(message, kind: :config, details: details)}
  end

  defp at(_stage, {:ok, _value} = result), do: result
  defp at(_stage, {:ok, _first, _second} = result), do: result
  defp at(_stage, :ok), do: :ok
  defp at(stage, {:error, reason}), do: {:error, stage, reason}

  defp unstage({:error, _stage, reason}), do: {:error, reason}
  defp unstage(result), do: result
end

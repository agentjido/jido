defmodule Jido.Agent.Runner do
  @moduledoc false

  alias Jido.Agent
  alias Jido.Agent.{Command, Turn}
  alias Jido.Agent.Plugin.Pipeline, as: AgentPlugin
  alias Jido.Error
  alias Jido.Signal
  alias Jido.Signal.Router

  @reserved_context_keys [:agent_id, :agent_state, :signal]
  @type stage :: :route | :prepare | :input | :compose | :validate

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
            agent: Jido.Agent.instance(),
            source_signal: Jido.Signal.t(),
            signal: Jido.Signal.t(),
            turn: Jido.Agent.Turn.t(),
            context: map(),
            exec_opts: keyword(),
            plugin_specs: [Jido.Agent.Plugin.Spec.t()]
          }
  end

  @doc false
  @spec run(Agent.instance(), Signal.t(), keyword()) ::
          {:ok, Agent.instance(), [struct()]} | {:error, term()}
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
  @spec prepare(Agent.instance(), Signal.t(), keyword()) ::
          {:ok, Prepared.t()} | {:error, term()}
  def prepare(%Agent{} = agent, %Signal{} = signal, opts) when is_list(opts) do
    agent
    |> prepare_direct(signal, opts, :normalize)
    |> unstage()
  end

  @doc false
  @spec prepare(Agent.instance(), Signal.t(), keyword(), [Jido.Plugin.Spec.t()]) ::
          {:ok, Prepared.t()} | {:error, term()}
  def prepare(%Agent{} = agent, %Signal{} = signal, opts, plugin_specs)
      when is_list(opts) and is_list(plugin_specs) do
    agent
    |> prepare_direct(signal, opts, {:prepared, plugin_specs})
    |> unstage()
  end

  @doc false
  @spec prepare_for_server(Command.t(), Signal.t(), keyword(), [Jido.Plugin.Spec.t()]) ::
          {:ok, Prepared.t()} | {:error, stage(), term()}
  def prepare_for_server(
        %Command{} = command,
        %Signal{} = source_signal,
        exec_opts,
        plugin_specs
      )
      when is_list(exec_opts) and is_list(plugin_specs) do
    with :ok <- at(:input, reject_reserved_context(command.context)),
         {:ok, selection} <- at(:route, select(command.agent, source_signal)),
         {:ok, plugin_specs} <- at(:prepare, plugin_specs(plugin_specs, :prepared)),
         {:ok, turn} <- at(:input, materialize(selection, source_signal, command.signal)) do
      {:ok,
       prepared(
         command.agent,
         source_signal,
         command.signal,
         turn,
         command.context,
         exec_opts,
         plugin_specs
       )}
    end
  end

  @doc false
  @spec finish_for_server(Prepared.t(), term()) ::
          {:ok, Agent.instance(), [struct()]} | {:error, stage(), term()}
  def finish_for_server(%Prepared{} = prepared, result), do: do_finish(prepared, result)

  @doc false
  @spec prepare_default_turn(Signal.t(), Agent.instance()) :: Agent.handle_result()
  def prepare_default_turn(%Signal{} = signal, %Agent{} = agent) do
    with {:ok, selection} <- default_selection(agent, signal),
         {:ok, turn} <- materialize(selection, signal, signal) do
      {:ok, turn}
    else
      {:error, error} -> {:error, normalize_routing_error(error, signal)}
    end
  end

  defp prepare_direct(agent, signal, opts, plugin_source) do
    {caller_context, exec_opts} = Keyword.pop(opts, :context, %{})

    with {:ok, caller_context} <- at(:input, Command.normalize_context(caller_context)),
         :ok <- at(:input, reject_reserved_context(caller_context)),
         {:ok, agent} <-
           at(:input, normalize_result_routing_error(Agent.validate_instance(agent), signal)),
         {:ok, signal} <- at(:input, Command.normalize_signal(signal)),
         {:ok, selection} <- at(:route, select(agent, signal)),
         {:ok, plugin_specs} <- at(:prepare, plugin_specs(agent.plugins, plugin_source)),
         {:ok, turn} <- at(:input, materialize(selection, signal, signal)) do
      {:ok, prepared(agent, signal, signal, turn, caller_context, exec_opts, plugin_specs)}
    end
  end

  defp prepared(agent, source_signal, signal, turn, caller_context, exec_opts, plugin_specs) do
    context =
      Map.merge(caller_context, %{
        agent_id: agent.id,
        agent_state: agent.state,
        signal: signal
      })

    %Prepared{
      agent: agent,
      source_signal: source_signal,
      signal: signal,
      turn: turn,
      context: context,
      exec_opts: exec_opts,
      plugin_specs: plugin_specs
    }
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
             AgentPlugin.run(
               {:ok, output, directives},
               prepared.agent.state,
               prepared.plugin_specs
             )
           ),
         {:ok, agent} <- at(:validate, Agent.transition_validated(prepared.agent, output)) do
      {:ok, agent, directives}
    end
  end

  defp select(%Agent{module: module} = agent, signal) do
    result =
      if module != Agent and function_exported?(module, :handle_signal, 2),
        do: custom_selection(agent, signal),
        else: default_selection(agent, signal)

    normalize_result_routing_error(result, signal)
  end

  defp default_selection(agent, signal) do
    with {:ok, router} <- Router.new(agent.routes),
         {:ok, target} <- route_first(router, signal),
         {:ok, executable, defaults} <- select_target(target) do
      {:ok, {:route, executable, defaults}}
    end
  end

  defp custom_selection(agent, signal) do
    case invoke_agent_callback(agent.module, :handle_signal, [signal, agent]) do
      {:ok, %Turn{} = turn} ->
        with {:ok, turn} <- Turn.bind_source(turn, signal),
             {:ok, turn} <- Turn.validate_selected(turn),
             do: {:ok, {:fixed, turn}}

      {:error, reason} ->
        {:error, reason}

      result ->
        {:error, invalid_callback_result(result, agent.module)}
    end
  end

  defp materialize({:fixed, turn}, _source_signal, _effective_signal), do: {:ok, turn}

  defp materialize({:route, executable, defaults}, source_signal, effective_signal) do
    with {:ok, input} <- merge_route_input(defaults, effective_signal),
         do: Turn.selected(executable, input, source_signal)
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

  defp reject_reserved_context(context) do
    keys = Enum.filter(@reserved_context_keys, &Map.has_key?(context, &1))

    if keys == [] do
      :ok
    else
      {:error,
       Error.validation_error("Agent command context contains reserved keys",
         details: %{keys: keys}
       )}
    end
  end

  defp route_first(router, signal) do
    case Router.route(router, signal) do
      {:ok, [target | _targets]} -> {:ok, target}
      {:error, error} -> {:error, error}
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

  defp plugin_specs(declarations, :normalize) do
    with {:ok, specs} <- Jido.Plugin.normalize_all(declarations),
         do: {:ok, Jido.Agent.Plugin.specs(specs)}
  end

  defp plugin_specs(specs, :prepared), do: {:ok, Jido.Agent.Plugin.specs(specs)}

  defp plugin_specs(_declarations, {:prepared, specs}),
    do: {:ok, Jido.Agent.Plugin.specs(specs)}

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

  defp at(_stage, {:ok, _value} = result), do: result
  defp at(_stage, {:ok, _first, _second} = result), do: result
  defp at(_stage, :ok), do: :ok
  defp at(stage, {:error, reason}), do: {:error, stage, reason}

  defp unstage({:error, _stage, reason}), do: {:error, reason}
  defp unstage(result), do: result
end

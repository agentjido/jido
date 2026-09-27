defmodule Jido.Agent.Runner do
  @moduledoc false

  alias Jido.Agent
  alias Jido.Agent.{Authoring, Callback, Command, Plugin, Turn, Validation}
  alias Jido.Agent.Plugin.Pipeline, as: PluginPipeline
  alias Jido.Error
  alias Jido.Signal
  alias Jido.Signal.Router

  @type stage :: :route | :prepare | :input | :compose | :validate

  defmodule Prepared do
    @moduledoc false

    @enforce_keys [
      :agent,
      :schema,
      :signal,
      :turn,
      :context,
      :exec_opts,
      :plugin_inputs,
      :plugin_specs
    ]
    defstruct @enforce_keys

    @type t :: %__MODULE__{
            agent: Jido.Agent.instance(),
            schema: Zoi.schema(),
            signal: Jido.Signal.t(),
            turn: Jido.Agent.Turn.t(),
            context: map(),
            exec_opts: keyword(),
            plugin_inputs: %{optional(module()) => Jido.Plugin.Input.t()},
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
    prepare_direct(agent, signal, opts) |> unstage()
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
    with :ok <- at(:input, Command.validate_caller_context(command.context)),
         {:ok, turn} <- at(:route, select(command.agent, source_signal)),
         {:ok, schema} <- at(:input, Plugin.compose_schema(command.agent.schema, plugin_specs)) do
      {:ok,
       prepared(
         command.agent,
         schema,
         command.signal,
         turn,
         command.context,
         exec_opts,
         command.plugin_inputs,
         Plugin.specs(plugin_specs)
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
    agent
    |> default_selection(signal)
    |> finish_selection(signal, agent.module)
    |> normalize_result_routing_error(signal)
  end

  defp prepare_direct(agent, signal, opts) do
    {caller_context, exec_opts} = Keyword.pop(opts, :context, %{})

    with {:ok, caller_context} <- at(:input, Command.normalize_context(caller_context)),
         :ok <- at(:input, Command.validate_caller_context(caller_context)),
         validation = Validation.validate_instance_with_plugins(agent),
         {:ok, agent, specs, schema} <-
           at(:input, normalize_result_routing_error(validation, signal)),
         {:ok, signal} <- at(:input, Command.normalize_signal(signal)),
         plugin_specs = Plugin.specs(specs),
         {:ok, plugin_inputs} <- at(:prepare, Plugin.prepare(agent, signal, plugin_specs)),
         {:ok, turn} <- at(:route, select(agent, signal)) do
      {:ok,
       prepared(
         agent,
         schema,
         signal,
         turn,
         caller_context,
         exec_opts,
         plugin_inputs,
         plugin_specs
       )}
    end
  end

  defp prepared(
         agent,
         schema,
         signal,
         turn,
         caller_context,
         exec_opts,
         plugin_inputs,
         plugin_specs
       ) do
    context =
      Map.merge(caller_context, %{
        agent_id: agent.id,
        agent_state: agent.state,
        plugin_inputs: plugin_inputs,
        signal: signal
      })

    %Prepared{
      agent: agent,
      schema: schema,
      signal: signal,
      turn: turn,
      context: context,
      exec_opts: exec_opts,
      plugin_inputs: plugin_inputs,
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
             PluginPipeline.run(
               {:ok, output, directives},
               prepared.agent,
               prepared.turn.source_signal,
               prepared.plugin_inputs,
               prepared.plugin_specs
             )
           ),
         {:ok, agent} <-
           at(:validate, Agent.transition_validated(prepared.agent, output, prepared.schema)) do
      {:ok, agent, directives}
    end
  end

  defp select(%Agent{module: module} = agent, signal) do
    result =
      if module != Agent and function_exported?(module, :handle_signal, 2),
        do: Callback.invoke(module, :handle_signal, [signal, agent]),
        else: default_selection(agent, signal)

    result
    |> finish_selection(signal, module)
    |> normalize_result_routing_error(signal)
  end

  defp default_selection(agent, signal) do
    with {:ok, router} <- Router.new(agent.routes),
         {:ok, target} <- route_first(router, signal),
         {executable, defaults} = Authoring.split_target(target),
         {:ok, input} <- merge_route_input(defaults || %{}, signal) do
      {:ok, %Turn{executable: executable, input: input}}
    end
  end

  defp finish_selection({:ok, %Turn{} = turn}, signal, _module) do
    with {:ok, turn} <- Turn.bind_source(turn, signal),
         do: Turn.validate_selected(turn)
  end

  defp finish_selection({:error, _reason} = error, _signal, _module), do: error

  defp finish_selection(result, _signal, module),
    do: {:error, invalid_callback_result(result, module)}

  defp normalize_exec_result({:ok, output}), do: normalize_exec_result({:ok, output, []})

  defp normalize_exec_result({:ok, output, directives})
       when is_map(output) and not is_struct(output),
       do: {:ok, output, List.wrap(directives)}

  defp normalize_exec_result({:ok, output, _directives}), do: invalid_state_output(output)
  defp normalize_exec_result({:error, reason}), do: {:error, reason}

  defp normalize_exec_result(result) do
    {:error,
     Error.execution_error("Agent executable returned an invalid result",
       details: %{code: :agent_invalid_callback_result, callback: :execute, result: result}
     )}
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

  defp merge_route_input(defaults, %Signal{} = signal) do
    case Turn.normalize_input(signal.data) do
      {:ok, input} ->
        {:ok, Map.merge(defaults, input)}

      {:error, _error} ->
        {:error,
         Error.validation_error("Agent Signal data must be a map, keyword list, or nil",
           field: :data,
           details: %{signal_id: signal.id, data: signal.data}
         )}
    end
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

  defp at(_stage, {:ok, _value} = result), do: result
  defp at(_stage, {:ok, _first, _second} = result), do: result
  defp at(_stage, {:ok, _first, _second, _third} = result), do: result
  defp at(_stage, :ok), do: :ok
  defp at(stage, {:error, reason}), do: {:error, stage, reason}

  defp unstage({:error, _stage, reason}), do: {:error, reason}
  defp unstage(result), do: result
end

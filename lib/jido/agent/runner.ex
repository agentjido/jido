defmodule Jido.Agent.Runner do
  @moduledoc false

  alias Jido.Agent
  alias Jido.Agent.{Command, Composition, Mutation, Plugin, Turn, Validation}
  alias Jido.Agent.Plugin.Pipeline, as: PluginPipeline
  alias Jido.AgentServer.Directive.ServerStop
  alias Jido.Error
  alias Jido.Signal

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
            plugin_specs: [Jido.Agent.Plugin.Spec.t()]
          }
  end

  @doc false
  @spec run(Agent.instance(), Signal.t(), keyword()) ::
          {:ok, Agent.instance(), [struct()]}
          | {:handoff, Agent.instance(), Jido.Instruction.t(), [struct()]}
          | {:error, term()}
  def run(%Agent{} = agent, %Signal{} = signal, opts) do
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
  def prepare(%Agent{} = agent, %Signal{} = signal, opts) do
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
      ) do
    with :ok <- at(:input, Command.validate_caller_context(command.context)),
         {:ok, turn} <- at(:route, select(command.agent, source_signal)),
         {:ok, schema} <-
           at(:input, Plugin.compose_schema_from_specs(command.agent.schema, plugin_specs)) do
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
  @spec prepare_handoff_for_server(
          Command.t(),
          Signal.t(),
          Jido.Instruction.t(),
          keyword(),
          [Jido.Plugin.Spec.t()]
        ) :: {:ok, Prepared.t()} | {:error, stage(), term()}
  def prepare_handoff_for_server(
        %Command{} = command,
        %Signal{} = source_signal,
        %Jido.Instruction{} = instruction,
        exec_opts,
        plugin_specs
      ) do
    turn = %Turn{
      executable: instruction,
      route: %{state: %{source: :output, path: []}, reply: nil},
      source_signal: source_signal
    }

    with :ok <- at(:input, Command.validate_caller_context(command.context)),
         {:ok, turn} <- at(:route, Turn.validate_selected(turn)),
         {:ok, schema} <-
           at(:input, Plugin.compose_schema_from_specs(command.agent.schema, plugin_specs)) do
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
          {:ok, Agent.instance(), [struct()]}
          | {:handoff, Agent.instance(), Jido.Instruction.t(), [struct()]}
          | {:error, stage(), term()}
  def finish_for_server(%Prepared{} = prepared, result), do: do_finish(prepared, result)

  defp prepare_direct(agent, signal, opts) do
    {caller_context, exec_opts} = Keyword.pop(opts, :context, %{})

    with {:ok, caller_context} <- at(:input, Command.normalize_context(caller_context)),
         :ok <- at(:input, Command.validate_caller_context(caller_context)),
         validation = Validation.validate_instance_with_plugins(agent),
         {:ok, agent, specs, schema} <- at(:input, validation),
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
        agent_module: agent.module,
        agent_signal_source: agent.signal_source,
        agent_state: agent.state,
        agent_topology: agent.topology,
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
      plugin_specs: plugin_specs
    }
  end

  defp finish(%Prepared{} = prepared, result) do
    prepared
    |> do_finish(result)
    |> unstage()
  end

  defp do_finish(
         %Prepared{} = prepared,
         {:handoff, %Jido.Instruction{} = instruction, directives}
       ) do
    with {:ok, directives} <-
           at(:compose, Jido.Agent.Contract.directives(prepared.agent, directives)),
         {:ok, state, directives} <-
           at(
             :compose,
             PluginPipeline.run(
               {:ok, prepared.agent.state, directives},
               prepared.agent,
               prepared.turn.source_signal,
               prepared.context.plugin_inputs,
               prepared.plugin_specs
             )
           ),
         result =
           if(Enum.any?(directives, &Mutation.mutation?/1),
             do: Composition.apply(prepared.agent, state, directives),
             else: Agent.transition_validated(prepared.agent, state, prepared.schema)
           ),
         {:ok, agent} <- at(:validate, result) do
      {:handoff, agent, instruction, directives}
    end
  end

  defp do_finish(%Prepared{} = prepared, result) do
    with {:ok, output, directives} <- at(:compose, normalize_exec_result(result)),
         {:ok, directives} <-
           at(:compose, Jido.Agent.Contract.directives(prepared.agent, directives)),
         {:ok, state, directives} <-
           at(:compose, project_route_result(prepared, output, directives)),
         {:ok, state, directives} <-
           at(
             :compose,
             PluginPipeline.run(
               {:ok, state, directives},
               prepared.agent,
               prepared.turn.source_signal,
               prepared.context.plugin_inputs,
               prepared.plugin_specs
             )
           ),
         result =
           if(Enum.any?(directives, &Mutation.mutation?/1),
             do: Composition.apply(prepared.agent, state, directives),
             else: Agent.transition_validated(prepared.agent, state, prepared.schema)
           ),
         {:ok, agent} <- at(:validate, result) do
      {:ok, agent, directives}
    end
  end

  defp select(agent, signal) do
    with {:ok, route} <- Jido.Agent.Route.select(agent, signal.type),
         {:ok, turn} <-
           (case route.handler do
              %{kind: kind, target: target} when kind in [:action, :flow] ->
                with {:ok, input} <- merge_route_input(route, signal),
                     do: {:ok, %Turn{executable: target, input: input, route: route}}

              handler ->
                {:ok,
                 %Turn{
                   executable: Jido.Agent.Turn.SignalHandler,
                   input: %{handler: handler},
                   route: route
                 }}
            end),
         {:ok, turn} <- Turn.bind_source(turn, signal) do
      Turn.validate_selected(turn)
    end
  end

  defp normalize_exec_result({:ok, output}), do: normalize_exec_result({:ok, output, []})

  defp normalize_exec_result({:ok, output, directives})
       when is_map(output) and not is_struct(output),
       do:
         with(
           {:ok, values} <- Jido.Agent.Data.list(directives, &{:ok, &1}),
           do: {:ok, output, values}
         )

  defp normalize_exec_result({:ok, output, _directives}) do
    {:error,
     Error.execution_error("Agent executable output must be a plain state map",
       details: %{code: :agent_invalid_callback_result, callback: :execute, output: output}
     )}
  end

  defp normalize_exec_result({:error, reason}), do: {:error, reason}

  defp normalize_exec_result(result) do
    {:error,
     Error.execution_error("Agent executable returned an invalid result",
       details: %{code: :agent_invalid_callback_result, callback: :execute, result: result}
     )}
  end

  defp project_route_result(%Prepared{} = prepared, output, directives) do
    route = prepared.turn.route

    with {:ok, state} <- project_state(route.state, output, prepared.agent.state),
         :ok <- Jido.Agent.Error.at(Jido.Agent.Data.plain_map(state), :state),
         {:ok, directives} <- project_reply(route.reply, output, directives, prepared) do
      {:ok, state, directives}
    end
  end

  defp project_state(:unchanged, _output, prepared_state), do: {:ok, prepared_state}

  defp project_state(selector, output, _prepared_state),
    do: select_output(selector, output, [:state])

  defp project_reply(nil, _output, directives, _prepared), do: {:ok, directives}

  defp project_reply(reply, output, directives, prepared) do
    with {:ok, data} <- select_output(reply.from, output, [:reply, :from]),
         {:ok, signal} <- build_reply_signal(reply.type, data, prepared) do
      {:ok, insert_reply(directives, Jido.Agent.Directive.reply(signal))}
    end
  end

  defp insert_reply(directives, reply) do
    index = if match?(%ServerStop{}, List.last(directives)), do: -2, else: -1
    List.insert_at(directives, index, reply)
  end

  defp select_output(%{source: :output, path: path}, output, mapping_path) do
    path
    |> Enum.with_index()
    |> Enum.reduce_while({:ok, output}, fn {key, index}, {:ok, value} ->
      case value do
        %{^key => selected} ->
          {:cont, {:ok, selected}}

        _ ->
          {:halt,
           Jido.Agent.Error.fail(
             :missing_output_field,
             mapping_path ++ [:path, index],
             "Selected output field is missing",
             %{key: key}
           )}
      end
    end)
  end

  defp build_reply_signal(type, data, %Prepared{} = prepared) do
    with {:ok, signal} <- Signal.new(type, data, source: prepared.agent.signal_source),
         {:ok, _request, trace} <- Signal.Trace.ensure(prepared.turn.source_signal),
         {:ok, signal} <- Signal.Trace.put(signal, trace),
         {:ok, signal} <-
           Signal.put_context(signal, "jidocausationid", prepared.turn.source_signal.id) do
      {:ok, signal}
    else
      {:error, reason} ->
        {:error,
         Error.execution_error("Agent route Reply Signal could not be built",
           details: %{reason: reason, type: type}
         )}
    end
  end

  defp merge_route_input(route, %Signal{} = signal) do
    case Turn.normalize_input(signal.data) do
      {:ok, input} ->
        Jido.Agent.Route.params(route, input)

      {:error, _error} ->
        {:error,
         Error.validation_error("Agent Signal data must be a map, keyword list, or nil",
           field: :data,
           details: %{signal_id: signal.id, data: signal.data}
         )}
    end
  end

  defp at(_stage, {:ok, _value} = result), do: result
  defp at(_stage, {:ok, _first, _second} = result), do: result
  defp at(_stage, {:ok, _first, _second, _third} = result), do: result
  defp at(_stage, :ok), do: :ok
  defp at(stage, {:error, reason}), do: {:error, stage, reason}

  defp unstage({:error, _stage, reason}), do: {:error, reason}
  defp unstage(result), do: result
end

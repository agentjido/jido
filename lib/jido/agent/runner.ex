defmodule Jido.Agent.Runner do
  @moduledoc false

  alias Jido.Agent.{Mutation, Plugin, Turn, Validation}
  alias Jido.Agent.Directive.ServerStop
  alias Jido.Agent.Plugin.Pipeline, as: PluginPipeline
  alias Jido.Error
  alias Jido.Signal

  @type stage :: :route | :prepare | :input | :compose | :validate
  @type admission :: %{
          required(:agent) => map(),
          required(:signal) => Signal.t(),
          required(:context) => map(),
          required(:plugin_inputs) => map()
        }

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
            agent: map(),
            schema: Jido.Joi.schema(),
            signal: Jido.Signal.t(),
            turn: Jido.Agent.Turn.t(),
            context: map(),
            exec_opts: keyword(),
            plugin_specs: [Jido.Plugin.Spec.Agent.t()]
          }
  end

  @doc false
  @spec run(map(), Signal.t(), keyword()) ::
          {:ok, map(), [struct()]}
          | {:handoff, map(), Jido.Instruction.t(), [struct()]}
          | {:error, term()}
  def run(agent, %Signal{} = signal, opts) do
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
  @spec prepare(map(), Signal.t(), keyword()) ::
          {:ok, Prepared.t()} | {:error, term()}
  def prepare(agent, %Signal{} = signal, opts) do
    prepare_direct(agent, signal, opts) |> unstage()
  end

  @doc false
  @spec transition_validated(map(), term(), Jido.Joi.schema()) ::
          {:ok, map()} | {:error, Exception.t()}
  def transition_validated(agent, next_state, schema) do
    with :ok <-
           Jido.Error.prefix_result_path(Jido.Agent.Schema.complete(schema, next_state), :state) do
      {:ok, %{agent | state: next_state}}
    end
  end

  @doc false
  @spec prepare_admitted(
          admission(),
          Signal.t(),
          keyword(),
          [Jido.Plugin.Spec.t()]
        ) ::
          {:ok, Prepared.t()} | {:error, stage(), term()}
  def prepare_admitted(
        %{
          agent: agent,
          signal: %Signal{} = signal,
          context: context,
          plugin_inputs: plugin_inputs
        },
        %Signal{} = source_signal,
        exec_opts,
        plugin_specs
      ) do
    agent_specs = Plugin.specs(plugin_specs)

    with :ok <- at(:input, Validation.validate_caller_context(context)),
         {:ok, turn} <-
           at(
             :route,
             select(
               agent,
               source_signal,
               plugin_inputs,
               agent_specs
             )
           ),
         {:ok, schema} <-
           at(:input, Plugin.compose_schema_from_specs(agent.schema, plugin_specs)) do
      {:ok,
       prepared(
         agent,
         schema,
         signal,
         turn,
         context,
         exec_opts,
         plugin_inputs,
         agent_specs
       )}
    end
  end

  @doc false
  @spec prepare_admitted_handoff(
          admission(),
          Signal.t(),
          Jido.Instruction.t(),
          keyword(),
          [Jido.Plugin.Spec.t()]
        ) :: {:ok, Prepared.t()} | {:error, stage(), term()}
  def prepare_admitted_handoff(
        %{
          agent: agent,
          signal: %Signal{} = signal,
          context: context,
          plugin_inputs: plugin_inputs
        },
        %Signal{} = source_signal,
        %Jido.Instruction{} = instruction,
        exec_opts,
        plugin_specs
      ) do
    agent_specs = Plugin.specs(plugin_specs)

    with :ok <- at(:input, Validation.validate_caller_context(context)),
         {:ok, selected} <-
           at(:route, select(agent, source_signal, plugin_inputs, agent_specs)),
         turn = %{
           selected
           | executable: instruction,
             execution_mode: execution_mode(instruction.kind),
             input: instruction.params
         },
         {:ok, turn} <- at(:route, Turn.validate_selected(turn)),
         {:ok, schema} <-
           at(:input, Plugin.compose_schema_from_specs(agent.schema, plugin_specs)) do
      {:ok,
       prepared(
         agent,
         schema,
         signal,
         turn,
         context,
         exec_opts,
         plugin_inputs,
         agent_specs
       )}
    end
  end

  @doc false
  @spec finish_for_server(Prepared.t(), term()) ::
          {:ok, map(), [struct()]}
          | {:handoff, map(), Jido.Instruction.t(), [struct()]}
          | {:error, stage(), term()}
  def finish_for_server(%Prepared{} = prepared, result), do: do_finish(prepared, result)

  defp prepare_direct(agent, signal, opts) do
    {caller_context, exec_opts} = Keyword.pop(opts, :context, %{})

    with {:ok, caller_context} <- at(:input, Validation.normalize_context(caller_context)),
         :ok <- at(:input, Validation.validate_caller_context(caller_context)),
         validation = Validation.validate_instance_with_plugins(agent),
         {:ok, agent, specs, schema} <- at(:input, validation),
         {:ok, signal} <- at(:input, Validation.normalize_signal(signal)),
         plugin_specs = Plugin.specs(specs),
         {:ok, plugin_inputs} <- at(:prepare, Plugin.prepare(agent, signal, plugin_specs)),
         {:ok, turn} <-
           at(:route, select(agent, signal, plugin_inputs, plugin_specs)) do
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
           at(:compose, Jido.Agent.Directive.directives(prepared.agent, directives)),
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
             do: Mutation.apply(prepared.agent, state, directives),
             else: transition_validated(prepared.agent, state, prepared.schema)
           ),
         {:ok, agent} <- at(:validate, result) do
      {:handoff, agent, instruction, directives}
    end
  end

  defp do_finish(%Prepared{} = prepared, result) do
    with {:ok, output, directives} <- at(:compose, normalize_exec_result(result)),
         {:ok, directives} <-
           at(:compose, Jido.Agent.Directive.directives(prepared.agent, directives)),
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
             do: Mutation.apply(prepared.agent, state, directives),
             else: transition_validated(prepared.agent, state, prepared.schema)
           ),
         {:ok, agent} <- at(:validate, result) do
      {:ok, agent, directives}
    end
  end

  defp select(agent, signal, plugin_inputs, plugin_specs) do
    with {:ok, route} <- Plugin.select_route(agent, signal, plugin_inputs, plugin_specs),
         {:ok, turn} <-
           (case route.handler do
              %{kind: kind, target: target} when kind in [:action, :flow] ->
                with {:ok, input} <- merge_route_input(route, signal),
                     do:
                       {:ok,
                        %Turn{
                          executable: target,
                          execution_mode: execution_mode(kind),
                          input: input,
                          route: route
                        }}

              handler ->
                {:ok,
                 %Turn{
                   executable: Jido.Agent.Turn.SignalHandler,
                   execution_mode: :managed,
                   input: %{handler: handler},
                   route: route
                 }}
            end),
         {:ok, turn} <- Turn.bind_source(turn, signal) do
      Turn.validate_selected(turn)
    end
  end

  defp execution_mode(:flow), do: :durable
  defp execution_mode(:action), do: :managed

  defp normalize_exec_result({:ok, output}), do: normalize_exec_result({:ok, output, []})

  defp normalize_exec_result({:ok, output, directives})
       when is_map(output) and not is_struct(output),
       do:
         with(
           {:ok, values} <- Jido.Agent.Schema.list(directives, &{:ok, &1}),
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
         :ok <- Jido.Error.prefix_result_path(Jido.Agent.Schema.plain_map(state), :state),
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
           Jido.Error.validation_result(
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
         {:ok, _request, trace} <- Signal.Context.ensure_trace(prepared.turn.source_signal),
         {:ok, signal} <-
           Signal.Context.put_trace(
             signal,
             Jido.Trace.with_causation(trace, prepared.turn.source_signal.id)
           ) do
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
           kind: :input,
           subject: :data,
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

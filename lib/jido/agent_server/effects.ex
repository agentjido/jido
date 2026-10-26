defmodule Jido.AgentServer.Effects do
  @moduledoc false

  alias Jido.Agent
  alias Jido.Agent.Directive.{Emit, Reply}
  alias Jido.Agent.Mutation
  alias Jido.AgentServer, as: Server
  alias Jido.AgentServer.Directive.{AgentSend, AgentStart, AgentStop, ParentSend}
  alias Jido.AgentServer.Directive.{ErrorReport, ProcessStart, ServerStop}
  alias Jido.AgentServer.TopologyRuntime
  alias Jido.Dispatch.Preparation, as: DispatchPreparation
  alias Jido.Signal
  alias Jido.Tracing.Context, as: TraceContext

  def validate_batch(directives, config) do
    limit = config.max_directives_per_turn

    if limit != :infinity and length(directives) > limit do
      {:error, :too_many_directives}
    else
      last = length(directives) - 1

      directives
      |> Enum.with_index()
      |> Enum.reduce_while(:ok, fn {directive, index}, :ok ->
        result =
          if match?(%ServerStop{}, directive) and index != last,
            do: {:error, :terminal_directive_not_last},
            else: validate(directive, config)

        if result == :ok, do: {:cont, :ok}, else: {:halt, result}
      end)
    end
  end

  def validate_dispatch(nil), do: :ok

  def validate_dispatch(dispatch) do
    case Signal.Dispatch.validate_opts(dispatch) do
      {:ok, _} -> :ok
      _ -> {:error, :invalid_dispatch}
    end
  end

  def next(%{effect_deadline: deadline}, now) when now >= deadline, do: :timed_out

  def next(%{effects: effects, effect_index: index}, _now) when index == length(effects),
    do: :done

  def next(%{effects: effects, effect_index: index}, _now),
    do: {:effect, Enum.at(effects, index)}

  def settle(%{effect_deadline: deadline}, _result, now) when now >= deadline,
    do: :timed_out

  def settle(_active, {:stop, reason}, _now), do: {:stop, reason}
  def settle(_active, {:reported_error, error}, _now), do: {:reported_error, error}
  def settle(_active, {:reply, signal}, _now), do: {:reply, signal}
  def settle(_active, :ok, _now), do: :continue
  def settle(_active, _result, _now), do: :failed

  def run(directive, handler, context) do
    do_run(directive, handler, context)
  catch
    _, _ -> {:error, :directive_failed}
  end

  defp do_run(%Emit{signal: signal, dispatch: dispatch}, _handler, context) do
    with {:ok, signal} <- prepare_outbound(signal, dispatch, context),
         do: dispatch_outbound(signal, dispatch, context)
  end

  defp do_run(%AgentStart{} = directive, _handler, context), do: start(directive, context)

  defp do_run(%AgentStop{name: name, reason: reason}, _handler, context),
    do: Server.stop_child(context.server, name, reason)

  defp do_run(%AgentSend{name: name, signal: signal}, _handler, context) do
    with {:ok, signal} <- prepare_outbound(signal, {:agent, name}, context),
         do: TopologyRuntime.send_agent(context.activation_state, name, signal)
  end

  defp do_run(%Reply{signal: signal}, _handler, context) do
    with {:ok, signal} <- prepare_outbound(signal, :reply, context),
         do: {:reply, signal}
  end

  defp do_run(%ParentSend{signal: signal}, _handler, context) do
    with {:ok, signal} <- prepare_outbound(signal, :parent, context),
         do: TopologyRuntime.parent_send(context.parent, signal)
  end

  defp do_run(%ServerStop{reason: reason}, _handler, _context), do: {:stop, reason}

  defp do_run(%ErrorReport{error: error, context: context}, _handler, _runtime),
    do: {:reported_error, {:reported_error, context, error}}

  defp do_run(%ProcessStart{child_spec: spec}, _handler, context) do
    case DynamicSupervisor.start_child(Jido.agent_supervisor_name(context.jido), spec) do
      {:ok, _} -> :ok
      {:ok, _, _} -> :ok
      :ignore -> :ok
      _ -> {:error, :spawn_process_failed}
    end
  end

  defp do_run(directive, handler, context), do: handler.(directive, context)

  def status(nil), do: nil
  def status(%{effect_deadline: nil}), do: nil
  def status(active), do: %{total: length(active.effects), completed: active.effect_index}

  def outcome(active, state_version, status) do
    %{
      turn_id: active.turn_id,
      status: status,
      completed: active.effect_index,
      total: length(active.effects),
      committed_version: state_version,
      stage: if(active.commit_hooks == [], do: :directive, else: :after_commit)
    }
  end

  def report_error(summary, agent_id, signal_id, target, jido) do
    signal = Signal.new!("jido.agent_server.error", summary, source: "/agent/#{agent_id}")

    signal =
      case TraceContext.propagate_to(signal, signal_id) do
        {:ok, traced} -> traced
        _ -> signal
      end

    case Signal.Dispatch.dispatch(signal, DispatchPreparation.inherit_bus_scope(target, jido)) do
      :ok -> :continue
      _ -> {:stop, :error_signal_failed}
    end
  end

  defp validate(%Emit{dispatch: dispatch}, config),
    do: validate_dispatch(dispatch || config.default_dispatch)

  # A durable turn can outlive its caller. The turn must still commit its state
  # after it resumes. ReplyGate.deliver/2 safely drops a reply when its gate is
  # nil or no longer alive, so the reply remains an ephemeral effect.
  defp validate(%Reply{}, %{durable: true}), do: :ok

  defp validate(%Reply{}, %{requester: requester}) when is_pid(requester) do
    if Process.alive?(requester), do: :ok, else: {:error, :requester_not_found}
  end

  defp validate(%Reply{}, _config), do: {:error, :requester_not_found}

  defp validate(%AgentStart{} = directive, config), do: validate_start(directive, config)

  defp validate(%AgentStop{name: name}, config), do: validate_runtime_target(name, config)
  defp validate(%AgentSend{name: name}, config), do: validate_target(name, config)
  defp validate(%ParentSend{}, %{parent: nil}), do: {:error, :parent_not_found}
  defp validate(%ParentSend{}, _), do: :ok
  defp validate(%ServerStop{}, _), do: :ok
  defp validate(%ErrorReport{}, _), do: :ok

  defp validate(%ProcessStart{child_spec: spec}, config) do
    if is_nil(config.jido) do
      {:error, :jido_instance_required}
    else
      child = Supervisor.child_spec(spec, [])

      case :supervisor.check_childspecs([child]) do
        :ok -> :ok
        _ -> {:error, :invalid_child_spec}
      end
    end
  catch
    _, _ -> {:error, :invalid_child_spec}
  end

  defp validate(directive, config) do
    cond do
      Mutation.mutation?(directive) ->
        :ok

      config.directive_handler != nil ->
        :ok

      Jido.Plugin.directive_owner(config.plugin_specs, directive) != nil ->
        :ok

      true ->
        {:error, :unsupported_directive}
    end
  end

  defp validate_target(name, config) do
    cond do
      is_nil(config.activation) -> {:error, :activation_required}
      not (is_atom(name) or is_binary(name)) or name in [nil, ""] -> {:error, :invalid_agent_name}
      String.starts_with?(to_string(name), "$topology/") -> {:error, :reserved_agent_name}
      true -> :ok
    end
  end

  defp validate_runtime_target(name, config) do
    with :ok <- validate_target(name, config) do
      if Enum.any?(config.agent.topology.agents, &(&1.name == name)),
        do: {:error, :topology_agent_requires_mutation},
        else: :ok
    end
  end

  defp validate_start(directive, config) do
    opts = Map.to_list(directive.opts)

    with :ok <- validate_runtime_target(directive.name, config),
         :ok <- local_node(directive.node),
         :ok <- validate_start_source(directive.agent, opts),
         :ok <-
           opts
           |> Keyword.drop([:id, :state, :name])
           |> Keyword.put_new(:persistence, false)
           |> Server.validate_defaults() do
      :ok
    end
  end

  defp validate_start_source(%Agent{} = agent, opts) do
    if Enum.any?([:id, :state], &Keyword.has_key?(opts, &1)),
      do: {:error, :instance_options_conflict},
      else:
        with(
          {:ok, agent} <- Agent.Validation.validate_instance(agent),
          do: Agent.validate_runtime_support(agent)
        )
  end

  defp validate_start_source(definition, _opts) do
    with {:ok, definition} <- Agent.Validation.resolve(definition),
         do: Agent.validate_runtime_support(definition)
  end

  defp local_node(target) when target in [nil, node()], do: :ok
  defp local_node(_), do: {:error, :remote_agent_start_not_supported}

  defp start(directive, context) do
    with {:ok, agent, options} <- prepare_start(directive, context.agent.id),
         {:ok, pid} <-
           Server.spawn_child(context.server, agent, directive.name,
             restart: directive.restart,
             server_options: options,
             meta: directive.meta
           ),
         do: Server.await_ready(pid)
  end

  defp prepare_start(directive, owner_id) do
    opts = Map.to_list(directive.opts)
    id = Keyword.get(opts, :id, owner_id <> "/" <> to_string(directive.name))
    state = Keyword.get(opts, :state, %{})
    options = opts |> Keyword.drop([:id, :state]) |> Keyword.put_new(:persistence, false)

    case directive.agent do
      %Agent{} = agent ->
        if Keyword.take(opts, [:id, :state]) != [],
          do: {:error, :instance_options_conflict},
          else: {:ok, agent, options}

      definition ->
        with {:ok, definition} <- Agent.Validation.resolve(definition),
             {:ok, agent} <- Agent.instantiate(definition, id: id, state: state),
             do: {:ok, agent, options}
    end
  end

  defp prepare_outbound(signal, target, context) do
    signal_context = %Jido.Plugin.SignalContext{
      turn_id: context.turn_id,
      agent_id: context.agent.id,
      source_signal: context.source_signal,
      effective_signal: context.effective_signal,
      turn_context: context.turn_context,
      target: target,
      state_version: context.state_version,
      plugin_state: nil,
      jido: context.jido,
      partition: context.partition
    }

    with {:ok, correlated} <- TraceContext.propagate_to(signal, context.signal_id),
         {:ok, prepared} <-
           Jido.AgentServer.Plugin.Callbacks.prepare_outbound(
             correlated,
             context.plugin_specs,
             context.plugin_refs,
             signal_context,
             context.agent.state
           ),
         :ok <- validate_outbound_correlation(target, correlated, prepared) do
      {:ok, prepared}
    end
  end

  defp validate_outbound_correlation(:reply, correlated, prepared) do
    before = {
      correlated.id,
      Signal.get_context(correlated, "jidocausationid"),
      Signal.Trace.get(correlated)
    }

    after_preparation = {
      prepared.id,
      Signal.get_context(prepared, "jidocausationid"),
      Signal.Trace.get(prepared)
    }

    if before == after_preparation,
      do: :ok,
      else: {:error, :invalid_reply_correlation}
  end

  defp validate_outbound_correlation(_target, _correlated, _prepared), do: :ok

  defp dispatch_outbound(signal, nil, context), do: TopologyRuntime.emit(context, signal)

  defp dispatch_outbound(signal, target, context) do
    Signal.Dispatch.dispatch(signal, DispatchPreparation.inherit_bus_scope(target, context.jido))
  end
end

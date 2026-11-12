defmodule Jido.AgentServer.Effects do
  @moduledoc false

  alias Jido.Agent.Directive.{Emit, Reply}
  alias Jido.AgentServer.Topology
  alias Jido.Signal
  alias Jido.Trace.Context, as: TraceContext

  def validate_batch(directives, config) do
    limit = config.max_directives_per_turn

    if limit != :infinity and length(directives) > limit do
      {:error, :too_many_directives}
    else
      Enum.reduce_while(directives, :ok, fn directive, :ok ->
        case validate(directive, config) do
          :ok -> {:cont, :ok}
          error -> {:halt, error}
        end
      end)
    end
  end

  def validate_dispatch(nil), do: :ok
  def validate_dispatch(:parent), do: :ok
  def validate_dispatch({:agent, name}) when is_atom(name) or is_binary(name), do: :ok

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

  def settle(_active, {:reply, signal}, _now), do: {:reply, signal}
  def settle(_active, :ok, _now), do: :continue
  def settle(_active, _result, _now), do: :failed

  def run(directive, handler, context) do
    do_run(directive, handler, context)
  catch
    _, _ -> {:error, :directive_failed}
  end

  @doc false
  def prepare_reply(nil, _context), do: {:ok, nil}

  def prepare_reply(%Signal{} = signal, context),
    do: prepare_outbound(signal, :reply, context)

  defp do_run(%Emit{signal: signal, dispatch: {:agent, name}}, _handler, context) do
    with {:ok, signal} <- prepare_outbound(signal, {:agent, name}, context),
         do: Topology.send_agent(context.activation_state, name, signal)
  end

  defp do_run(%Emit{signal: signal, dispatch: :parent}, _handler, context) do
    with {:ok, signal} <- prepare_outbound(signal, :parent, context),
         do: Topology.parent_send(context.parent, signal)
  end

  defp do_run(%Emit{signal: signal, dispatch: dispatch}, _handler, context) do
    with {:ok, signal} <- prepare_outbound(signal, dispatch, context),
         do: dispatch_outbound(signal, dispatch, context)
  end

  defp do_run(%Reply{signal: signal}, _handler, context) do
    with {:ok, signal} <- prepare_outbound(signal, :reply, context),
         do: {:reply, signal}
  end

  defp do_run(_directive, _handler, _context), do: {:error, :unsupported_directive}

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

  defp validate(%Emit{dispatch: {:agent, name}}, config), do: validate_target(name, config)
  defp validate(%Emit{dispatch: :parent}, %{parent: nil}), do: {:error, :parent_not_found}
  defp validate(%Emit{dispatch: :parent}, _config), do: :ok
  defp validate(%Emit{dispatch: dispatch}, config), do: validate_dispatch(dispatch || config.default_dispatch)

  # A reply is part of the accepted Turn result. A cast discards it, and an
  # abandoned or stopped requester does not invalidate the Agent commit.
  defp validate(%Reply{}, _config), do: :ok

  defp validate(directive, config) do
    if Jido.Plugin.directive_owner(config.plugin_specs, directive) != nil,
      do: :ok,
      else: {:error, :unsupported_directive}
  end

  defp validate_target(name, config) do
    cond do
      is_nil(config.activation) -> {:error, :activation_required}
      not (is_atom(name) or is_binary(name)) or name in [nil, ""] -> {:error, :invalid_agent_name}
      String.starts_with?(to_string(name), "$topology/") -> {:error, :reserved_agent_name}
      true -> :ok
    end
  end

  defp prepare_outbound(signal, target, context) do
    signal_context = %Jido.Plugin.Context{
      phase: :signal,
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
      Signal.Context.get_trace(correlated)
    }

    after_preparation = {
      prepared.id,
      Signal.get_context(prepared, "jidocausationid"),
      Signal.Context.get_trace(prepared)
    }

    if before == after_preparation,
      do: :ok,
      else: {:error, :invalid_reply_correlation}
  end

  defp validate_outbound_correlation(_target, _correlated, _prepared), do: :ok

  defp dispatch_outbound(signal, nil, context), do: Topology.emit(context, signal)

  defp dispatch_outbound(signal, target, context) do
    Signal.Dispatch.dispatch(signal, Signal.Dispatch.inherit_bus_scope(target, context.jido))
  end
end

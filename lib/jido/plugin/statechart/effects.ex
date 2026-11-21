defmodule Jido.Plugin.Statechart.Effects do
  @moduledoc false

  require Logger

  alias Jido.{AgentServer, Signal}
  alias Jido.Instance.Names
  alias Jido.Statechart
  alias Jido.Plugin.Statechart, as: Plugin
  alias Jido.Statechart.{BasicHTTP, SCXML, Sends}

  def dispatch(runtime, session, effects, context) do
    if session.status != :active, do: Sends.cancel(runtime, :all)

    effects =
      if session.status == :completed and session.parent,
        do: batch_completion(effects),
        else: effects

    {timers, effects} = Enum.split_with(effects, &timer_effect?/1)
    timer_result = dispatch_effects(timers, runtime, context)

    result =
      if context.jido && Enum.any?(effects, &child_lifecycle_effect?/1) do
        dispatch_lifecycle(effects, runtime, context)
      else
        dispatch_effects(effects, runtime, context)
      end

    if timer_result == :ok, do: result, else: timer_result
  end

  def event_signal(%{name: name, data: data} = message, owner) do
    {data, context} =
      if is_map(data) or is_nil(data),
        do: {data, %{}},
        else: {%{content: data}, %{"scxmlcontent" => true}}

    context =
      if message[:sendid], do: Map.put(context, "scxmlsendid", message.sendid), else: context

    context =
      if message[:invokeid],
        do: Map.put(context, "scxmlinvokeid", message.invokeid),
        else: context

    context = Map.put(context, "scxmlorigin", SCXML.location(owner))
    Signal.new!(name, data, source: "/statechart", extensions: context)
  end

  defp dispatch_lifecycle(effects, runtime, context) do
    supervisor = Names.task_supervisor(context.jido)

    # Committed child cleanup must survive a directive timeout.
    case launch(supervisor, fn -> dispatch_effects(effects, runtime, context) end) do
      {:ok, task} ->
        case Task.yield(task, :infinity) do
          {:ok, result} -> result
          {:exit, reason} -> {:error, reason}
        end

      {:error, reason} ->
        {stops, remaining} = Enum.split_with(effects, &match?({:stop, _}, &1))

        if stops != [],
          do: Sends.start_task(runtime, fn -> dispatch_effects(stops, runtime, context) end)

        remaining =
          Enum.map(remaining, fn
            {:start, _module, %{child: child}, _data} ->
              {:start_rejected, child, reason}

            effect ->
              effect
          end)

        dispatch_effects(remaining, runtime, context)
    end
  end

  defp launch(supervisor, run) do
    {:ok, Task.Supervisor.async_nolink(supervisor, run)}
  rescue
    error in RuntimeError -> {:error, error}
  catch
    :exit, reason -> {:error, reason}
  end

  defp timer_effect?({:cancel_send, _}), do: true
  defp timer_effect?({kind, _, _, delay}) when kind in [:send_event, :http_post], do: delay > 0
  defp timer_effect?(_effect), do: false

  defp child_lifecycle_effect?({:start, _, _, _}), do: true
  defp child_lifecycle_effect?({:stop, _}), do: true
  defp child_lifecycle_effect?(_effect), do: false

  defp dispatch_effects(effects, runtime, context) do
    Enum.reduce(effects, :ok, fn effect, result ->
      case dispatch_committed(effect, runtime, context) do
        :ok -> result
        {:error, _reason} = error -> if(result == :ok, do: error, else: result)
      end
    end)
  end

  defp batch_completion(effects) do
    case Enum.reverse(effects) do
      [{:done, %{agent: parent} = invocation, value} | previous] ->
        {replies, remaining} =
          previous
          |> Enum.reverse()
          |> Enum.split_with(&match?({:send_event, ^parent, _, 0}, &1))

        messages = Enum.map(replies, fn {:send_event, _, message, 0} -> message end)
        remaining ++ [{:child_completed, invocation, messages, value}]

      _ ->
        effects
    end
  end

  defp dispatch_committed(effect, runtime, context) do
    dispatch_committed(effect, runtime, context.jido, context.agent_id, partition: context.partition)
  catch
    :exit, reason -> {:error, reason}
  end

  defp dispatch_committed({:cancel_send, id}, runtime, _instance, _owner, _opts),
    do: Sends.cancel(runtime, id)

  defp dispatch_committed(_effect, _runtime, nil, _owner, _opts),
    do: {:error, :statechart_invocation_requires_jido_instance}

  defp dispatch_committed(
         {:child_completed, %{agent: parent, id: id, child: child}, messages, value},
         runtime,
         instance,
         _owner,
         opts
       ) do
    signal =
      Signal.new!(
        "statechart.child_completed",
        %{child: child, id: id, messages: messages, value: value},
        source: "/statechart"
      )

    with server when is_pid(server) <- Jido.whereis_agent(instance, parent, opts),
         {:ok, _task} <- Sends.start_task(runtime, fn -> deliver_completion(server, signal) end) do
      :ok
    else
      nil -> {:error, :statechart_agent_not_found}
      {:error, _reason} = error -> error
    end
  end

  defp dispatch_committed({kind, target, event, delay}, runtime, instance, owner, opts)
       when kind in [:send_event, :http_post] and delay > 0 do
    with sender when is_pid(sender) <- Jido.whereis_agent(instance, owner, opts),
         :ok <-
           Sends.schedule(runtime, event[:sendid], delay, fn ->
             deliver = fn ->
               if active?(sender),
                 do: dispatch_effect({kind, target, event, 0}, instance, owner, opts)
             end

             case Task.Supervisor.start_child(Names.task_supervisor(instance), deliver) do
               {:ok, _pid} -> :ok
               {:error, _reason} -> AgentServer.cast(sender, communication_error(event))
             end
           end) do
      :ok
    else
      nil -> {:error, :statechart_agent_not_found}
      {:error, _reason} = error -> error
    end
  end

  defp dispatch_committed(effect, _runtime, instance, owner, opts),
    do: dispatch_effect(effect, instance, owner, opts)

  defp dispatch_effect({:start, module, %{id: id, child: child}, data}, instance, agent, opts) do
    parent = %{agent: agent, id: id, child: child}

    case start_child(instance, module, parent, data, opts) do
      :ok ->
        :ok

      {:error, _reason} = error ->
        cast(instance, agent, effect_error("error.execution", %{child: child}), opts)
        error
    end
  end

  defp dispatch_effect({:start_rejected, child, reason}, instance, agent, opts) do
    cast(instance, agent, effect_error("error.execution", %{child: child}), opts)
    {:error, reason}
  end

  defp dispatch_effect({:stop, child}, instance, _agent, opts) do
    case Jido.whereis_agent(instance, child, opts) do
      server when is_pid(server) ->
        cancelled = cancel_child(server)
        stopped = Jido.stop_agent(instance, server, opts)

        case cancelled do
          {:ok, %{status: :committed}} -> stopped
          {:ok, %{error: reason}} -> {:error, reason}
          {:error, _reason} = error -> error
        end

      _ ->
        :ok
    end
  end

  defp dispatch_effect({:send, child, signal}, instance, owner, opts) do
    case cast(instance, child, signal, opts) do
      {:error, :statechart_agent_not_found} = error ->
        cast(instance, owner, effect_error("error.communication", %{child: child}), opts)
        error

      result ->
        result
    end
  end

  defp dispatch_effect({:log, label, value}, instance, agent, _opts) do
    :telemetry.execute([:jido, :statechart, :log], %{}, %{
      instance: instance,
      agent: agent,
      label: label,
      value: value
    })

    Logger.info(fn -> [label || "", " ", inspect(value)] end)
  end

  defp dispatch_effect({:http_post, target, event, 0}, instance, owner, opts) do
    with sender when is_pid(sender) <- Jido.whereis_agent(instance, owner, opts) do
      post(sender, target, event)
    else
      _ -> {:error, :statechart_agent_not_found}
    end
  end

  defp dispatch_effect({:send_event, agent, message, 0}, instance, owner, opts) do
    case cast(instance, agent, event_signal(message, owner), opts) do
      {:error, _reason} = error ->
        cast(instance, owner, communication_error(message), opts)
        error

      :ok ->
        :ok
    end
  end

  defp deliver_completion(parent, signal, first_attempt? \\ true) do
    AgentServer.call(parent, signal, timeout: :infinity, admission_timeout: :infinity)
  catch
    :exit, {reason, {:gen_statem, :call, _args}} ->
      completion_delivery_failed(parent, signal, reason)

    :exit, reason ->
      completion_delivery_failed(parent, signal, reason)
  else
    {:ok, %{status: :committed}} ->
      :ok

    {:error, {:overloaded, %{limit: limit}}} ->
      if first_attempt? do
        :telemetry.execute([:jido, :statechart, :completion_retry], %{count: 1}, %{
          parent: parent,
          child: signal.data.child,
          limit: limit
        })
      end

      Process.sleep(25)
      deliver_completion(parent, signal, false)

    {:ok, %{status: status}} ->
      completion_delivery_failed(parent, signal, {:turn_status, status})

    {:error, reason} ->
      completion_delivery_failed(parent, signal, reason)
  end

  defp completion_delivery_failed(parent, signal, reason) do
    # The host application selects which structured metadata to show.
    # credo:disable-for-next-line Credo.Check.Warning.MissedMetadataKeyInLoggerConfig
    Logger.warning("Statechart child completion delivery failed",
      parent: parent,
      child: signal.data.child,
      reason: reason
    )
  end

  defp cancel_child(server) do
    AgentServer.call(server, Signal.new!("statechart.cancel", %{}, source: "/statechart"))
  catch
    :exit, reason -> {:error, reason}
  end

  defp cast(instance, id, signal, opts) do
    case Jido.whereis_agent(instance, id, opts) do
      pid when is_pid(pid) -> AgentServer.cast(pid, signal)
      _ -> {:error, :statechart_agent_not_found}
    end
  end

  defp start_child(instance, module, %{agent: agent, child: child} = parent, data, opts) do
    with :ok <- check_invocation(instance, agent, child, opts),
         {:ok, parent_address} <- Jido.agent_address(instance, agent, opts),
         {:ok, child_address} <- Jido.agent_address(instance, child, opts),
         {:ok, server} <- Jido.start_agent(instance, module, [id: child] ++ opts) do
      with :ok <- AgentServer.await_ready(server),
           :ok <- check_invocation(instance, agent, child, opts),
           {:ok, _ownership} <-
             Jido.transfer_agent_ownership(instance, child_address, parent_address,
               expected: nil,
               request_id: child
             ),
           {:ok, %{status: :committed}} <- initialize_child(server, data, parent) do
        :ok
      else
        failed ->
          Jido.stop_agent(instance, server, opts)
          {:error, {:statechart_child_initialization, failed}}
      end
    end
  end

  defp initialize_child(server, data, parent) do
    AgentServer.call(server, Statechart.initialization_signal(data, parent))
  catch
    :exit, reason -> {:error, reason}
  end

  defp check_invocation(instance, agent, child, opts) do
    with server when is_pid(server) <- Jido.whereis_agent(instance, agent, opts),
         %{agent: %{state: %{statechart: %{session: %{status: :active} = session}}}} <-
           AgentServer.snapshot(server),
         %{} <- Plugin.find_invocation(session, &(&1.child == child)) do
      :ok
    else
      _ -> {:error, :inactive_invocation}
    end
  catch
    :exit, _reason -> {:error, :inactive_invocation}
  end

  defp post(sender, target, event) do
    case BasicHTTP.post(target, event) do
      :ok ->
        :ok

      {:error, _reason} = error ->
        AgentServer.cast(sender, communication_error(event))
        error
    end
  end

  defp effect_error(event, fields),
    do: Signal.new!("statechart.effect_error", Map.put(fields, :event, event), source: "/statechart")

  defp communication_error(message),
    do: effect_error("error.communication", Map.take(message, [:sendid]))

  defp active?(sender) do
    Process.alive?(sender) and
      match?(
        %{agent: %{state: %{statechart: %{session: %{status: :active}}}}},
        AgentServer.snapshot(sender)
      )
  end
end

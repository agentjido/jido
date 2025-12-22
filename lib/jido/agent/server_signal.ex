defmodule Jido.Agent.Server.Signal do
  @moduledoc false
  alias Jido.Signal
  alias Jido.Signal.DispatchHelpers
  alias Jido.Signal.Trace.Propagate

  alias Jido.Agent.Server.State, as: ServerState

  @config %{
    separator: ".",
    jido_prefix: "jido",
    agent_prefix: "agent",
    cmd_prefix: "cmd",
    output_prefix: "out",
    event_prefix: "event",
    error_prefix: "err"
  }

  @agent_base [@config.jido_prefix, @config.agent_prefix]
  @cmd_base @agent_base ++ [@config.cmd_prefix]
  @event_base @agent_base ++ [@config.event_prefix]
  @error_base @agent_base ++ [@config.error_prefix]
  @output_base @agent_base ++ [@config.output_prefix]

  @doc false
  def type({:cmd, :state}), do: @cmd_base ++ ["state"]
  def type({:cmd, :queue_size}), do: @cmd_base ++ ["queuesize"]
  def type({:cmd, :set}), do: @cmd_base ++ ["set"]
  def type({:cmd, :validate}), do: @cmd_base ++ ["validate"]
  def type({:cmd, :plan}), do: @cmd_base ++ ["plan"]
  def type({:cmd, :run}), do: @cmd_base ++ ["run"]
  def type({:cmd, :cmd}), do: @cmd_base ++ ["cmd"]
  def type({:cmd, :enqueue}), do: @cmd_base ++ ["enqueue"]
  def type({:event, :started}), do: @event_base ++ ["started"]
  def type({:event, :stopped}), do: @event_base ++ ["stopped"]

  def type({:event, :transition_succeeded}),
    do: @event_base ++ ["transition", "succeeded"]

  def type({:event, :transition_failed}), do: @event_base ++ ["transition", "failed"]
  def type({:event, :queue_overflow}), do: @event_base ++ ["queue", "overflow"]
  def type({:event, :queue_cleared}), do: @event_base ++ ["queue", "cleared"]
  def type({:event, :mode_changed}), do: @event_base ++ ["mode", "changed"]

  def type({:event, :process_started}), do: @event_base ++ ["process", "started"]
  def type({:event, :process_restarted}), do: @event_base ++ ["process", "restarted"]
  def type({:event, :process_terminated}), do: @event_base ++ ["process", "terminated"]
  def type({:event, :process_failed}), do: @event_base ++ ["process", "failed"]

  def type({:event, :debugger_pre_signal}), do: @event_base ++ ["debugger", "pre", "signal"]
  def type({:event, :debugger_post_signal}), do: @event_base ++ ["debugger", "post", "signal"]

  def type({:err, :execution_error}), do: @error_base ++ ["execution", "error"]
  def type({:out, :instruction_result}), do: @output_base ++ ["instruction", "result"]
  def type({:out, :signal_result}), do: @output_base ++ ["signal", "result"]

  def type({category, _subtype}) when category not in [:cmd, :event, :err, :out], do: nil
  def type(_), do: nil

  @doc false
  def cmd_signal(type, state, params \\ %{}, opts \\ %{})

  def cmd_signal(:set, %ServerState{} = state, params, _opts),
    do: build(state, %{type: type({:cmd, :set}), data: params})

  def cmd_signal(:validate, %ServerState{} = state, params, _opts),
    do: build(state, %{type: type({:cmd, :validate}), data: params})

  def cmd_signal(:plan, %ServerState{} = state, params, _context),
    do: build(state, %{type: type({:cmd, :plan}), data: params})

  def cmd_signal(:run, %ServerState{} = state, _opts, _params),
    do: build(state, %{type: type({:cmd, :run})})

  def cmd_signal(:cmd, %ServerState{} = state, {_instructions, params}, _opts),
    do: build(state, %{type: type({:cmd, :cmd}), data: params})

  def cmd_signal(:state, _state, _params, _opts),
    do: build(nil, %{type: type({:cmd, :state})})

  def cmd_signal(:enqueue, %ServerState{} = state, instruction, _opts),
    do: build(state, %{type: type({:cmd, :enqueue}), data: instruction})

  @doc false
  def cmd_signal(_, _, _, _), do: nil

  def event_signal(type, state, params \\ %{}, extra_attrs \\ %{})

  def event_signal(:started, %ServerState{} = state, params, extra_attrs),
    do: build(state, Map.merge(%{type: type({:event, :started}), data: params}, extra_attrs))

  def event_signal(:transition_succeeded, %ServerState{} = state, params, extra_attrs),
    do:
      build(
        state,
        Map.merge(%{type: type({:event, :transition_succeeded}), data: params}, extra_attrs)
      )

  def event_signal(:transition_failed, %ServerState{} = state, params, extra_attrs),
    do:
      build(
        state,
        Map.merge(%{type: type({:event, :transition_failed}), data: params}, extra_attrs)
      )

  def event_signal(:queue_overflow, %ServerState{} = state, params, extra_attrs),
    do:
      build(state, Map.merge(%{type: type({:event, :queue_overflow}), data: params}, extra_attrs))

  def event_signal(:queue_cleared, %ServerState{} = state, params, extra_attrs),
    do:
      build(state, Map.merge(%{type: type({:event, :queue_cleared}), data: params}, extra_attrs))

  def event_signal(:mode_changed, %ServerState{} = state, params, extra_attrs),
    do: build(state, Map.merge(%{type: type({:event, :mode_changed}), data: params}, extra_attrs))

  def event_signal(:stopped, %ServerState{} = state, params, extra_attrs),
    do: build(state, Map.merge(%{type: type({:event, :stopped}), data: params}, extra_attrs))

  def event_signal(:process_terminated, %ServerState{} = state, params, extra_attrs),
    do:
      build(
        state,
        Map.merge(%{type: type({:event, :process_terminated}), data: params}, extra_attrs)
      )

  def event_signal(:process_failed, %ServerState{} = state, params, extra_attrs),
    do:
      build(state, Map.merge(%{type: type({:event, :process_failed}), data: params}, extra_attrs))

  def event_signal(:process_restarted, %ServerState{} = state, params, extra_attrs),
    do:
      build(
        state,
        Map.merge(%{type: type({:event, :process_restarted}), data: params}, extra_attrs)
      )

  def event_signal(:process_started, %ServerState{} = state, params, extra_attrs),
    do:
      build(
        state,
        Map.merge(%{type: type({:event, :process_started}), data: params}, extra_attrs)
      )

  def event_signal(:debugger_pre_signal, %ServerState{} = state, params, extra_attrs),
    do:
      build(
        state,
        Map.merge(%{type: type({:event, :debugger_pre_signal}), data: params}, extra_attrs)
      )

  def event_signal(:debugger_post_signal, %ServerState{} = state, params, extra_attrs),
    do:
      build(
        state,
        Map.merge(%{type: type({:event, :debugger_post_signal}), data: params}, extra_attrs)
      )

  def event_signal(_, _, _, _), do: nil

  def err_signal(type, state, error, params \\ %{}, extra_attrs \\ %{})

  def err_signal(
        :execution_error,
        %ServerState{} = state,
        %_{} = error,
        _params,
        extra_attrs
      ),
      do:
        build(state, Map.merge(%{type: type({:err, :execution_error}), data: error}, extra_attrs))

  def err_signal(_, _, _, _, _), do: nil

  def out_signal(type, state, result, params \\ %{}, extra_attrs \\ %{})

  def out_signal(:instruction_result, %ServerState{} = state, result, _params, extra_attrs),
    do:
      build(
        state,
        Map.merge(%{type: type({:out, :instruction_result}), data: result}, extra_attrs)
      )

  def out_signal(:signal_result, %ServerState{} = state, result, _params, extra_attrs),
    do: build(state, Map.merge(%{type: type({:out, :signal_result}), data: result}, extra_attrs))

  def out_signal(_, _, _, _, _), do: nil

  def join_type(type) when is_list(type) do
    Enum.join(type, @config.separator)
  end

  def join_type(type) when is_binary(type), do: type

  defp build(%ServerState{} = state, attrs) do
    agent_name = get_agent_name(state.agent)

    base = %{
      id: Jido.Util.generate_id(),
      subject: build_subject(agent_name, state.agent.id),
      source: build_source(state)
    }

    type = join_type(attrs.type)
    attrs = Map.put(attrs, :type, type)

    signal =
      base
      |> Map.merge(attrs)
      |> Propagate.inject_trace_context(state)
      |> Signal.new!()

    # Use extension API instead of deprecated jido_dispatch field
    if state.dispatch do
      {:ok, signal} = DispatchHelpers.put_dispatch(signal, state.dispatch)
      signal
    else
      signal
    end
  end

  defp build(nil, attrs) do
    type = join_type(attrs.type)
    attrs = Map.put(attrs, :type, type)

    attrs
    |> Propagate.inject_trace_context(%{})
    |> Signal.new!()
  end

  defp build_source(%ServerState{current_signal: %Signal{id: id}}) when not is_nil(id),
    do: id

  defp build_source(%ServerState{agent: %{id: id}}) when not is_nil(id),
    do: "agent:#{id}"

  defp build_source(_), do: nil

  defp build_subject(nil, agent_id), do: "jido://agent/#{agent_id}"
  defp build_subject(agent_name, agent_id), do: "jido://agent/#{agent_name}/#{agent_id}"

  defp get_agent_name(nil), do: nil

  defp get_agent_name(agent) do
    try do
      String.downcase(agent.__struct__.name())
    rescue
      _ -> nil
    end
  end

  # Helper functions for event types
  def process_started, do: join_type(type({:event, :process_started}))
  def process_terminated, do: join_type(type({:event, :process_terminated}))
end

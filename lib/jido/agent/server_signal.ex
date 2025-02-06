defmodule Jido.Agent.Server.Signal do
  use ExDbug, enabled: false
  alias Jido.Signal
  alias Jido.Error
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

  def type({:cmd, :state}), do: @cmd_base ++ ["state"]
  def type({:cmd, :queue_size}), do: @cmd_base ++ ["queuesize"]
  def type({:cmd, :set}), do: @cmd_base ++ ["set"]
  def type({:cmd, :validate}), do: @cmd_base ++ ["validate"]
  def type({:cmd, :plan}), do: @cmd_base ++ ["plan"]
  def type({:cmd, :run}), do: @cmd_base ++ ["run"]
  def type({:cmd, :cmd}), do: @cmd_base ++ ["cmd"]

  def type({:event, :started}), do: @event_base ++ ["started"]
  def type({:event, :stopped}), do: @event_base ++ ["stopped"]

  def type({:event, :transition_succeeded}),
    do: @event_base ++ ["transition", "succeeded"]

  def type({:event, :transition_failed}), do: @event_base ++ ["transition", "failed"]
  def type({:event, :queue_overflow}), do: @event_base ++ ["queue", "overflow"]
  def type({:event, :queue_cleared}), do: @event_base ++ ["queue", "cleared"]

  def type({:event, :process_started}), do: @event_base ++ ["process", "started"]
  def type({:event, :process_restarted}), do: @event_base ++ ["process", "restarted"]
  def type({:event, :process_terminated}), do: @event_base ++ ["process", "terminated"]
  def type({:event, :process_failed}), do: @event_base ++ ["process", "failed"]

  def type({:err, :execution_error}), do: @error_base ++ ["execution", "error"]
  def type({:out, :instruction_result}), do: @output_base ++ ["instruction", "result"]
  def type({:out, :signal_result}), do: @output_base ++ ["signal", "result"]

  def type({category, _subtype}) when category not in [:cmd, :event, :err, :out], do: nil
  def type(_), do: nil

  def cmd_signal(type, state, params \\ %{}, opts \\ %{})

  def cmd_signal(:set, %ServerState{} = state, params, opts) when is_map(opts),
    do: build(state, %{type: type({:cmd, :set}), data: params, jido_opts: opts})

  def cmd_signal(:validate, %ServerState{} = state, params, opts) when is_map(opts),
    do: build(state, %{type: type({:cmd, :validate}), data: params, jido_opts: opts})

  def cmd_signal(:plan, %ServerState{} = state, params, context),
    do: build(state, %{type: type({:cmd, :plan}), data: params, jido_opts: context})

  def cmd_signal(:run, %ServerState{} = state, opts, _params) when is_map(opts),
    do: build(state, %{type: type({:cmd, :run}), jido_opts: opts})

  def cmd_signal(:cmd, %ServerState{} = state, {_instructions, params}, opts) when is_map(opts),
    do: build(state, %{type: type({:cmd, :cmd}), data: params, jido_opts: opts})

  def cmd_signal(:state, _state, _params, _opts),
    do: build(nil, %{type: type({:cmd, :state})})

  def cmd_signal(_, _, _, _), do: nil

  def event_signal(type, state, params \\ %{})

  def event_signal(:started, %ServerState{} = state, params),
    do: build(state, %{type: type({:event, :started}), data: params})

  def event_signal(:transition_succeeded, %ServerState{} = state, params),
    do: build(state, %{type: type({:event, :transition_succeeded}), data: params})

  def event_signal(:transition_failed, %ServerState{} = state, params),
    do: build(state, %{type: type({:event, :transition_failed}), data: params})

  def event_signal(:queue_overflow, %ServerState{} = state, params),
    do: build(state, %{type: type({:event, :queue_overflow}), data: params})

  def event_signal(:queue_cleared, %ServerState{} = state, params),
    do: build(state, %{type: type({:event, :queue_cleared}), data: params})

  def event_signal(:stopped, %ServerState{} = state, params),
    do: build(state, %{type: type({:event, :stopped}), data: params})

  def event_signal(:process_terminated, %ServerState{} = state, params),
    do: build(state, %{type: type({:event, :process_terminated}), data: params})

  def event_signal(:process_failed, %ServerState{} = state, params),
    do: build(state, %{type: type({:event, :process_failed}), data: params})

  def event_signal(:process_restarted, %ServerState{} = state, params),
    do: build(state, %{type: type({:event, :process_restarted}), data: params})

  def event_signal(:process_started, %ServerState{} = state, params),
    do: build(state, %{type: type({:event, :process_started}), data: params})

  def event_signal(_, _, _), do: nil

  def err_signal(type, state, error, _params \\ %{})

  def err_signal(:execution_error, %ServerState{} = state, %Error{} = error, _params),
    do: build(state, %{type: type({:err, :execution_error}), data: error})

  def err_signal(_, _, _, _), do: nil

  def out_signal(type, state, result, _params \\ %{})

  def out_signal(:instruction_result, %ServerState{} = state, result, _params),
    do: build(state, %{type: type({:out, :instruction_result}), data: result})

  def out_signal(:signal_result, %ServerState{} = state, result, _params),
    do: build(state, %{type: type({:out, :signal_result}), data: result})

  def out_signal(_, _, _, _), do: nil

  def join_type(type) when is_list(type) do
    Enum.join(type, @config.separator)
  end

  def join_type(type) when is_binary(type), do: type

  defp build(%ServerState{} = state, attrs) do
    # Use the original signal's ID if this is a result signal
    signal_id = if state.current_signal, do: state.current_signal.id, else: UUID.uuid4()

    base = %{
      id: signal_id,
      source: "jido://agent/#{state.agent.id}",
      jido_dispatch: state.dispatch
    }

    type = join_type(attrs.type)
    attrs = Map.put(attrs, :type, type)

    base
    |> Map.merge(attrs)
    |> Signal.new!()
  end

  defp build(nil, attrs) do
    type = join_type(attrs.type)
    attrs = Map.put(attrs, :type, type)
    Signal.new!(attrs)
  end

  # Helper functions for event types
  def process_started, do: join_type(type({:event, :process_started}))
  def process_terminated, do: join_type(type({:event, :process_terminated}))
end

defmodule Jido.AgentServer.ActiveTurn do
  @moduledoc false

  alias Jido.Agent.Turn.Outcome
  alias Jido.Signal
  alias Jido.Signal.ID

  @schema Zoi.struct(
            __MODULE__,
            %{
              turn_id: Zoi.string(description: "Stable Turn identifier"),
              source_signal: Zoi.struct(Signal, description: "Signal received by the Server"),
              effective_signal:
                Zoi.struct(Signal, description: "Signal after Plugin preparation")
                |> Zoi.optional(),
              caller: Zoi.any(description: "Optional synchronous caller") |> Zoi.optional(),
              exec_handle:
                Zoi.any(description: "Caller-owned Jido.Exec handle") |> Zoi.optional(),
              prepared: Zoi.any(description: "Prepared Agent command") |> Zoi.optional(),
              turn_context:
                Zoi.map(description: "Prepared transient Turn context") |> Zoi.default(%{}),
              start_version: Zoi.integer(description: "Agent version at Turn start"),
              committed_version:
                Zoi.integer(description: "Committed Agent version") |> Zoi.optional(),
              directive_count: Zoi.integer(description: "Directive count") |> Zoi.default(0),
              directive_completed_count:
                Zoi.integer(description: "Completed Directive count") |> Zoi.default(0),
              directive_failure_count:
                Zoi.integer(description: "Directive failure count") |> Zoi.default(0),
              directive_failed_index:
                Zoi.integer(description: "Zero-based failed Directive index") |> Zoi.optional(),
              started_monotonic:
                Zoi.integer(description: "Monotonic Turn start time in milliseconds"),
              span: Zoi.any(description: "Signal telemetry span") |> Zoi.optional(),
              telemetry_span:
                Zoi.any(description: "Semantic Turn telemetry span") |> Zoi.optional()
            }
          )

  @type t :: unquote(Zoi.type_spec(@schema))

  @enforce_keys Zoi.Struct.enforce_keys(@schema)
  defstruct Zoi.Struct.struct_fields(@schema)

  @spec schema() :: Zoi.schema()
  def schema, do: @schema

  @spec new(Signal.t(), term(), non_neg_integer(), term()) :: t()
  def new(source_signal, caller, start_version, span) do
    %__MODULE__{
      turn_id: ID.generate!(),
      source_signal: source_signal,
      caller: caller,
      start_version: start_version,
      started_monotonic: System.monotonic_time(:millisecond),
      span: span
    }
  end

  @spec begin_execution(t(), term(), term()) :: t()
  def begin_execution(%__MODULE__{} = active, handle, prepared) do
    turn_context = Map.drop(prepared.context, [:agent_id, :agent_state, :signal])

    %{
      active
      | effective_signal: prepared.signal,
        exec_handle: handle,
        prepared: prepared,
        turn_context: turn_context
    }
  end

  @spec mark_committed(t(), non_neg_integer(), non_neg_integer()) :: t()
  def mark_committed(%__MODULE__{} = active, version, directive_count) do
    %{
      active
      | caller: nil,
        exec_handle: nil,
        prepared: nil,
        committed_version: version,
        directive_count: directive_count
    }
  end

  @spec mark_directive_completed(t()) :: t()
  def mark_directive_completed(%__MODULE__{} = active) do
    %{active | directive_completed_count: active.directive_completed_count + 1}
  end

  @spec mark_directive_failed(t()) :: t()
  def mark_directive_failed(%__MODULE__{} = active) do
    %{
      active
      | directive_failure_count: active.directive_failure_count + 1,
        directive_failed_index: active.directive_completed_count
    }
  end

  @spec outcome(t(), String.t(), Outcome.status(), Outcome.stage(), term()) :: Outcome.t()
  def outcome(%__MODULE__{} = active, agent_id, status, stage, error) do
    started_at = ID.extract_timestamp(active.turn_id)
    finished_at = System.system_time(:millisecond)
    duration_ms = max(System.monotonic_time(:millisecond) - active.started_monotonic, 0)

    skipped =
      active.directive_count - active.directive_completed_count - active.directive_failure_count

    Outcome.new!(%{
      id: active.turn_id,
      agent_id: agent_id,
      source_signal: active.source_signal,
      effective_signal: active.effective_signal,
      status: status,
      stage: stage,
      committed?: not is_nil(active.committed_version),
      state_version_before: active.start_version,
      state_version_after: active.committed_version,
      error: error,
      directives: %{
        total: active.directive_count,
        completed: active.directive_completed_count,
        failed: active.directive_failure_count,
        failed_index: active.directive_failed_index,
        skipped: max(skipped, 0)
      },
      started_at: started_at,
      finished_at: finished_at,
      duration_ms: duration_ms
    })
  end
end

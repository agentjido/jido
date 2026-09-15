defmodule Jido.Agent.Turn.Outcome do
  @moduledoc """
  The terminal runtime outcome for one admitted Agent Turn.

  The Agent Server creates this record when a Turn stops. It records whether
  the Agent committed, where processing stopped, and the result of post-commit
  Plugin notifications and Directive work. Notification failure uses stage
  `:after_commit`; it does not count as a failed Directive. It contains no
  process handles or private Server state.
  """

  @type status :: :succeeded | :failed | :cancelled | :timed_out | :indeterminate
  @type stage :: :prepare | :execute | :finalize | :commit | :after_commit | :directive

  @type directive_summary :: %{
          total: non_neg_integer(),
          completed: non_neg_integer(),
          failed: 0 | 1,
          failed_index: non_neg_integer() | nil,
          skipped: non_neg_integer()
        }

  @type t :: %__MODULE__{
          id: String.t(),
          agent_id: String.t(),
          source_signal: Jido.Signal.t(),
          effective_signal: Jido.Signal.t() | nil,
          status: status(),
          stage: stage(),
          committed?: boolean(),
          state_version_before: non_neg_integer(),
          state_version_after: non_neg_integer() | nil,
          error: term(),
          directives: directive_summary(),
          started_at: non_neg_integer(),
          finished_at: non_neg_integer(),
          duration_ms: non_neg_integer()
        }

  @enforce_keys [
    :id,
    :agent_id,
    :source_signal,
    :status,
    :stage,
    :committed?,
    :state_version_before,
    :started_at,
    :finished_at,
    :duration_ms
  ]

  defstruct @enforce_keys ++
              [
                effective_signal: nil,
                state_version_after: nil,
                error: nil,
                directives: %{
                  total: 0,
                  completed: 0,
                  failed: 0,
                  failed_index: nil,
                  skipped: 0
                }
              ]
end

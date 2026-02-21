defmodule Jido.Actions.Status do
  @moduledoc """
  Base actions for agent status management.

  These actions provide standard patterns for managing agent completion states,
  which integrate with `Jido.Await` for event-driven coordination.

  ## Status Convention

  Jido agents use a `status` field in their state to signal completion:
  - `:idle` - Agent is waiting for work
  - `:working` - Agent is processing
  - `:completed` - Agent finished successfully
  - `:failed` - Agent encountered an error

  `Jido.Await` watches for `:completed` or `:failed` status to unblock waiters.

  ## Usage

      use Jido.Agent,
        name: "status_agent",
        signal_routes: [
          {"work.done", Jido.Actions.Status.MarkCompleted},
          {"work.error", Jido.Actions.Status.MarkFailed}
        ]
  """

  defmodule SetStatus do
    @moduledoc """
    Set the agent's status field to any value.

    ## Schema

    - `status` - Status atom to set (required)

    ## Example

        {Jido.Actions.Status.SetStatus, %{status: :working}}
    """
    use Jido.Action,
      name: "set_status",
      description: "Set the agent's status field",
      schema: [
        status: [type: :atom, required: true, doc: "Status to set"]
      ]

    def run(%{status: status}, _context) do
      {:ok, %{status: status}}
    end
  end

  defmodule MarkCompleted do
    @moduledoc """
    Mark the agent as completed with an optional result.

    Sets `status: :completed` and optionally `last_answer` with the result.
    This triggers `Jido.Await` waiters to unblock.

    ## Schema

    - `result` - Optional result value to store in `last_answer`

    ## Example

        # Simple completion
        {"work.done", Jido.Actions.Status.MarkCompleted}

        # With result
        {Jido.Actions.Status.MarkCompleted, %{result: "Answer: 42"}}
    """
    use Jido.Action,
      name: "mark_completed",
      description: "Mark agent as completed with optional result",
      schema: [
        result: [type: :any, default: nil, doc: "Optional result value"]
      ]

    def run(%{result: result}, _context) do
      state = %{status: :completed}
      state = if result, do: Map.put(state, :last_answer, result), else: state
      {:ok, state}
    end
  end

  defmodule MarkFailed do
    @moduledoc """
    Mark the agent as failed with an error reason.

    Sets `status: :failed` and stores the error in the `error` field.
    This triggers `Jido.Await` waiters to unblock.

    ## Schema

    - `reason` - Error reason (default: :unknown_error)

    ## Example

        {"work.error", Jido.Actions.Status.MarkFailed}

        {Jido.Actions.Status.MarkFailed, %{reason: :timeout}}
    """
    use Jido.Action,
      name: "mark_failed",
      description: "Mark agent as failed with error reason",
      schema: [
        reason: [type: :any, default: :unknown_error, doc: "Error reason"]
      ]

    def run(%{reason: reason}, _context) do
      {:ok, %{status: :failed, error: reason}}
    end
  end

  defmodule MarkWorking do
    @moduledoc """
    Mark the agent as actively working.

    Sets `status: :working` to indicate the agent is processing.

    ## Schema

    - `task_id` - Optional task identifier

    ## Example

        {"work.start", Jido.Actions.Status.MarkWorking}
    """
    use Jido.Action,
      name: "mark_working",
      description: "Mark agent as actively working",
      schema: [
        task_id: [type: :any, default: nil, doc: "Optional task identifier"]
      ]

    def run(%{task_id: task_id}, _context) do
      state = %{status: :working}
      state = if task_id, do: Map.put(state, :current_task, task_id), else: state
      {:ok, state}
    end
  end

  defmodule MarkIdle do
    @moduledoc """
    Mark the agent as idle and ready for work.

    Sets `status: :idle` to indicate the agent is waiting.

    ## Example

        {"reset", Jido.Actions.Status.MarkIdle}
    """
    use Jido.Action,
      name: "mark_idle",
      description: "Mark agent as idle and ready",
      schema: []

    def run(_params, _context) do
      {:ok, %{status: :idle}}
    end
  end
end

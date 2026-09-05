defmodule Jido.Examples.Factory.Protocol do
  @moduledoc "Shared, typed commands and events for the two factory examples."

  @doc false
  def command_schema do
    Zoi.object(%{
      operation: Zoi.enum([:submit, :status, :pause, :resume, :cancel]),
      request_id: Zoi.string() |> Zoi.min(1),
      job_id: Zoi.string() |> Zoi.default(""),
      goal: Zoi.string() |> Zoi.max(20_000) |> Zoi.default("")
    })
  end

  @doc false
  def batch_schema do
    Zoi.object(%{
      request_id: Zoi.string() |> Zoi.min(1),
      goals: Zoi.list(goal_schema()) |> Zoi.min(1) |> Zoi.max(20)
    })
  end

  @doc false
  def goal_schema do
    Zoi.string()
    |> Zoi.min(1)
    |> Zoi.max(20_000)
    |> Zoi.refine({__MODULE__, :validate_goal, []})
  end

  @doc false
  def validate_goal(goal, _opts),
    do: if(String.trim(goal) == "", do: {:error, "must not be blank"}, else: :ok)

  @doc false
  def event_schema do
    Zoi.object(%{
      event_id: Zoi.string(),
      job_id: Zoi.string(),
      status: Zoi.string(),
      detail: Zoi.string()
    })
  end

  @doc false
  def event(state, job, detail) do
    sequence = state.sequence + 1

    signal =
      Jido.Signal.new!(
        "factory.event",
        %{
          event_id: "#{job.id}:#{sequence}",
          job_id: job.id,
          status: Atom.to_string(job.status),
          detail: detail
        },
        source: "/examples/factory"
      )

    next = %{state | sequence: sequence, events: Enum.take(state.events ++ [signal.data], -100)}
    {next, Jido.Agent.Directive.emit_to_parent(signal)}
  end

  @doc false
  def invalid(message), do: {:error, Jido.Action.Error.validation_error(message)}
end

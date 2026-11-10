defmodule Jido.Durable.Status do
  @moduledoc """
  Public state for one durable Flow execution.

  `next_wake_at` is a UTC Unix time in milliseconds. A host can schedule a
  later `Jido.Durable.resume/3` call for that time. Cron hosts deliver their
  occurrence as a `Jido.Signal`.
  """

  alias Jido.Durable.Ref
  alias Jido.Exec.Runtime
  alias Runic.Workflow

  @enforce_keys [:ref, :state, :waits]
  defstruct [:ref, :state, :waits, :next_wake_at]

  @type state :: :ready | :running | :waiting | :completed | :failed | :uncertain
  @type t :: %__MODULE__{
          ref: Ref.t(),
          state: state(),
          waits: [Jido.Exec.Wait.t()],
          next_wake_at: non_neg_integer() | nil
        }

  @doc false
  @spec new(Ref.t(), Workflow.t(), boolean()) :: t()
  def new(%Ref{} = ref, %Workflow{} = workflow, active? \\ false) do
    waits = Runtime.pending_waits(workflow)

    %__MODULE__{
      ref: ref,
      state: state(workflow, waits, active?),
      waits: waits,
      next_wake_at: Jido.Exec.Wait.next_deadline(waits)
    }
  end

  defp state(_workflow, _waits, true), do: :running
  defp state(_workflow, [_ | _], false), do: :waiting

  defp state(workflow, [], false) do
    case Jido.Exec.result(workflow) do
      {:ok, _value} -> :completed
      {:ok, _value, _effects} -> :completed
      {:handoff, _instruction, _effects} -> :completed
      {:error, %{details: %{outcome: :uncertain}}} -> :uncertain
      {:error, _error} -> if(Workflow.is_runnable?(workflow), do: :ready, else: :failed)
    end
  end
end

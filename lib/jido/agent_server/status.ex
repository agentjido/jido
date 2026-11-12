defmodule Jido.AgentServer.Status do
  @moduledoc """
  The process-neutral semantic state of one resident Agent activation.

  The value separates logical Agent life, current work, and process residency.
  It does not expose internal process phases or process handles.
  """

  alias Jido.Agent.Ref
  alias Jido.Exec.Wait

  @type lifecycle :: :alive | :deleted
  @type work_state :: :idle | :running | :waiting | :faulted
  @type residency :: :passivated | :activating | :active | :passivating

  @enforce_keys [
    :agent_ref,
    :agent_activation_id,
    :lifecycle,
    :work_state,
    :residency,
    :ready?,
    :durability,
    :agent_revision,
    :persistence_revision,
    :admission,
    :queue_depth
  ]
  defstruct [
    :agent_ref,
    :agent_activation_id,
    :lifecycle,
    :work_state,
    :residency,
    :ready?,
    :durability,
    :agent_revision,
    :persistence_revision,
    :admission,
    :queue_depth,
    :active_turn_id,
    :last_outcome,
    :effects,
    waits: []
  ]

  @type t :: %__MODULE__{
          agent_ref: Ref.t(),
          agent_activation_id: String.t() | nil,
          lifecycle: lifecycle(),
          work_state: work_state(),
          residency: residency(),
          ready?: boolean(),
          durability: :memory | :durable,
          agent_revision: non_neg_integer(),
          persistence_revision: non_neg_integer() | nil,
          admission: :open | :quiescing | :quiesced | :blocked,
          queue_depth: non_neg_integer(),
          active_turn_id: String.t() | nil,
          waits: [Wait.t()],
          last_outcome: map() | nil,
          effects: :none | :pending
        }

  @doc false
  def new(runtime_phase, data, _mailbox) do
    %__MODULE__{
      agent_ref: data.agent_ref,
      agent_activation_id: data.agent_activation_id,
      lifecycle: :alive,
      work_state: work_state(runtime_phase),
      residency: residency(runtime_phase),
      ready?: runtime_phase not in [:restoring, :initializing],
      durability: if(data.persistence in [nil, false], do: :memory, else: :durable),
      agent_revision: data.agent_revision,
      persistence_revision: data.persistence_revision,
      admission: data.admission_mode,
      queue_depth: MapSet.size(data.postponed),
      active_turn_id: if(data.active, do: data.active.turn_id),
      waits: if(data.active, do: data.active.waits, else: []),
      last_outcome: safe_outcome(data.last_outcome),
      effects: effects(data.active)
    }
  end

  @doc false
  def passivated(ref, agent_revision, persistence_revision, turn) do
    %__MODULE__{
      agent_ref: ref,
      agent_activation_id: nil,
      lifecycle: :alive,
      work_state: if(open_turn?(turn), do: :waiting, else: :idle),
      residency: :passivated,
      ready?: false,
      durability: :durable,
      agent_revision: agent_revision,
      persistence_revision: persistence_revision,
      admission: :quiesced,
      queue_depth: 0,
      active_turn_id: if(open_turn?(turn), do: turn.id),
      waits: [],
      last_outcome: nil,
      effects: :none
    }
  end

  @doc false
  def process_neutral?(value) when is_pid(value) or is_port(value) or is_reference(value), do: false
  def process_neutral?(value) when is_function(value), do: false
  def process_neutral?([]), do: true

  def process_neutral?([head | tail]),
    do: process_neutral?(head) and process_neutral?(tail)

  def process_neutral?(value) when is_tuple(value), do: value |> Tuple.to_list() |> process_neutral?()

  def process_neutral?(value) when is_map(value) do
    value = if is_struct(value), do: Map.from_struct(value), else: value
    Enum.all?(value, fn {key, item} -> process_neutral?(key) and process_neutral?(item) end)
  end

  def process_neutral?(_value), do: true

  defp work_state(:waiting), do: :waiting
  defp work_state(:faulted), do: :faulted
  defp work_state(phase) when phase in [:idle, :restoring, :initializing, :quiesced], do: :idle
  defp work_state(_phase), do: :running

  defp residency(phase) when phase in [:restoring, :initializing], do: :activating
  defp residency(:passivating), do: :passivating
  defp residency(_phase), do: :active

  defp effects(%{effects: effects}) when effects != [], do: :pending
  defp effects(_active), do: :none

  defp safe_outcome(outcome) when is_map(outcome),
    do: Map.take(outcome, [:turn_id, :status, :stage, :committed?])

  defp safe_outcome(_outcome), do: nil

  defp open_turn?(%{status: status}) when status in [:running, :released], do: true
  defp open_turn?(_turn), do: false
end

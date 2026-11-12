defmodule Jido.AgentServer.Status do
  @moduledoc """
  A process-neutral view of one AgentServer runtime.

  Status contains stable identity, lifecycle stage, queue counts, durable Turn
  data, waits, and terminal summaries. It does not expose PIDs, ports,
  references, functions, monitors, tasks, timers, or ownership tokens.
  """

  @typedoc "The current activation form."
  @type activation :: :bare | :supervised

  @typedoc "The current public lifecycle phase."
  @type phase :: :initializing | :idle | :handoff_pending | :waiting | :running

  @typedoc "A stable parent relationship without its live activation handle."
  @type parent :: %{
          optional(:agent_id) => String.t(),
          optional(:tag) => atom() | String.t(),
          optional(:placement) => :owned | :independent,
          optional(:policy) => :stop | :continue | :emit_orphan,
          optional(:restart) => :permanent | :transient | :temporary,
          optional(:jido) => atom(),
          optional(:partition) => String.t() | nil,
          optional(:meta) => map()
        }

  @typedoc "A public AgentServer runtime snapshot."
  @type t :: %__MODULE__{
          phase: phase(),
          ready?: boolean(),
          plugin_count: non_neg_integer(),
          activation: activation(),
          parent: parent() | nil,
          agent_id: String.t(),
          jido: atom() | nil,
          partition: String.t() | nil,
          effects: map() | nil,
          last_effect_outcome: map() | nil,
          state_version: non_neg_integer(),
          durable_turn: map() | nil,
          error_count: non_neg_integer(),
          last_outcome: map() | nil,
          owner_count: non_neg_integer(),
          idle_timeout: non_neg_integer() | :infinity,
          idle_policy: :stop | :hibernate,
          admission: map(),
          active: map() | nil,
          waits: [Jido.Exec.Wait.t()]
        }

  defstruct [
    :phase,
    :ready?,
    :plugin_count,
    :activation,
    :parent,
    :agent_id,
    :jido,
    :partition,
    :effects,
    :last_effect_outcome,
    :state_version,
    :durable_turn,
    :error_count,
    :last_outcome,
    :owner_count,
    :idle_timeout,
    :idle_policy,
    :admission,
    :active,
    waits: []
  ]

  @doc false
  def new(runtime_phase, data, mailbox) do
    %__MODULE__{
      phase: public_phase(runtime_phase),
      ready?: runtime_phase not in [:restoring, :initializing],
      plugin_count: length(data.plugin_specs),
      activation: if(data.activation, do: :supervised, else: :bare),
      parent: parent(data.parent),
      agent_id: data.agent.id,
      jido: data.jido,
      partition: data.partition,
      effects: Jido.AgentServer.Effects.status(data.active),
      last_effect_outcome: data.last_effect_outcome,
      state_version: data.state_version,
      durable_turn: durable_turn(data.server_turn),
      error_count: data.error_count,
      last_outcome: data.last_outcome,
      owner_count: map_size(data.owners),
      idle_timeout: data.idle_timeout,
      idle_policy: data.idle_policy,
      admission: %{
        mode: data.admission_mode,
        postponed: MapSet.size(data.postponed),
        limit: data.max_postponed_signals,
        message_queue_len: mailbox
      },
      active: active(data.active, runtime_phase),
      waits: if(data.active, do: data.active.waits, else: [])
    }
  end

  @doc false
  def process_neutral?(value) when is_pid(value) or is_port(value) or is_reference(value), do: false
  def process_neutral?(value) when is_function(value), do: false
  def process_neutral?(value) when is_list(value), do: Enum.all?(value, &process_neutral?/1)
  def process_neutral?(value) when is_tuple(value), do: value |> Tuple.to_list() |> process_neutral?()

  def process_neutral?(value) when is_map(value) do
    value = if is_struct(value), do: Map.from_struct(value), else: value

    value
    |> Enum.all?(fn {key, item} -> process_neutral?(key) and process_neutral?(item) end)
  end

  def process_neutral?(_value), do: true

  defp public_phase(phase) when phase in [:restoring, :initializing], do: :initializing
  defp public_phase(:idle), do: :idle
  defp public_phase(:handoff_pending), do: :handoff_pending
  defp public_phase(:waiting), do: :waiting
  defp public_phase(_phase), do: :running

  defp durable_turn(nil), do: nil
  defp durable_turn(turn), do: Map.take(turn, [:id, :status, :chain_id, :chain_order])

  defp active(nil, _phase), do: nil

  defp active(active, phase) do
    active
    |> Map.take([:turn_id, :signal_id, :start_version])
    |> Map.put(
      :committed_version,
      if(active.outcome && active.outcome.committed?,
        do: active.outcome.state_version_after,
        else: nil
      )
    )
    |> Map.put(:stage, phase)
  end

  defp parent(nil), do: nil

  defp parent(parent) do
    parent
    |> Map.take([:agent_id, :tag, :placement, :policy, :restart, :jido, :partition])
    |> Map.put(:meta, safe_meta(Map.get(parent, :meta, %{})))
  end

  defp safe_meta(meta) do
    if is_map(meta) and not is_struct(meta) and process_neutral?(meta), do: meta, else: %{}
  end
end

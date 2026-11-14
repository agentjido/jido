defmodule Jido.Plugin.Timer.DeliveryAdapter do
  @moduledoc """
  External delivery contract for durable Timer hosts.

  An adapter persists recurring definitions and delayed Signals outside the
  AgentServer. The `reconcile/2` callback replaces the full active cron
  definition set for one Agent. Fixed-delay intervals are not supported by
  this adapter contract. `schedule/3` must persist one delayed Signal before it
  returns `:ok`. All callbacks must accept the same input more than once.

  When an adapter is configured, the Timer runtime does not start local
  delivery timers. A local retry timer can retry failed reconciliation. The
  adapter owns durable delivery and acknowledgement. Delivery is at least once.

  Recurring definitions become durable when `reconcile/2` returns `:ok`. A
  delayed Signal becomes durable when `schedule/3` returns `:ok`. The adapter
  cannot close the gap between the Agent commit and these calls. A host that
  needs atomic storage must add an outbox.
  """

  alias Jido.Signal

  @typedoc "Stable identity and commit data for one Timer adapter call."
  @type context :: %{
          required(:agent_id) => String.t(),
          required(:jido) => atom() | nil,
          required(:partition) => term(),
          required(:scope) => term(),
          required(:state_version) => non_neg_integer(),
          optional(:turn_id) => String.t() | nil
        }

  @typedoc "One validated recurring definition owned by Timer Agent state."
  @type recurring_definition :: %{
          required(:cron_expression) => String.t(),
          required(:message) => Signal.t(),
          required(:timezone) => String.t(),
          optional(:generation) => 0..2_147_483_647
        }

  @typedoc "The full desired cron definition set for one Agent."
  @type recurring_definitions :: %{optional(term()) => recurring_definition()}

  @callback reconcile(context(), recurring_definitions()) :: :ok | {:error, term()}
  @callback schedule(context(), non_neg_integer(), Signal.t()) :: :ok | {:error, term()}
end

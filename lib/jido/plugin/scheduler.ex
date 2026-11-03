defmodule Jido.Plugin.Scheduler do
  @moduledoc """
  Adds delayed and recurring Signals to an Agent.

  The Plugin owns the `:scheduler` part of Agent state. This state contains the
  recurring schedule definitions. Its supervised runtime owns timers and job
  references.

  A delayed Signal from `schedule/2` is a runtime-only one-shot. It is not in
  Agent state or in a checkpoint. A Scheduler, Agent, or VM restart can discard
  it. Recurring definitions can restore future timers when Agent state is
  restored. Slots that pass while the runtime is offline are not replayed.

  Pass `generation: integer` (0 through 2,147,483,647) to `cron/4` to add logical occurrence
  metadata. Use a new generation when replacing or recreating a schedule, and
  retain it across restore. `occurrence/1` reads the metadata. Signal data stays
  unchanged. Omit generation for the existing plain ticks.

      directive = Jido.Plugin.Scheduler.cron("report", "0 * * * *", tick, generation: 1)

  In the tick Action, read the metadata from `context.signal`:

      {:ok, occurrence} = Jido.Plugin.Scheduler.occurrence(context.signal)
      occurrence.id

  `:retry_delay_ms` sets the delay after a recurring job cannot start (default
  1,000; positive integer up to 4,294,967,295). A valid finite cron expression
  with no future occurrence is dormant, not failed. It stays in Agent state so
  it can be cancelled or replaced, and it does not prevent other jobs from
  starting during restore.

  The optional Plugin option `:time_scale` accepts a `SchedEx.TimeScale` module
  with `now/1` and `speedup/0` callbacks for controlled time. Its `speedup/0`
  result must be a positive number, and `now/1` must return a `DateTime`. It
  affects recurring schedules only. The default uses current time. Runtime clock
  state is not saved in the Agent checkpoint.

  The optional `:delivery_adapter` moves delayed and recurring delivery to an
  external host. The Scheduler still owns definitions, cron calculation,
  generations, and occurrence metadata. With this option, the AgentServer
  starts no local schedule delivery timers. The adapter owns persistence,
  leases, delivery, and acknowledgement.

  An application can install one adapter for its AgentServer instances:

      agent_server: [
        plugin_runtime_options: [
          {Jido.Plugin.Scheduler, delivery_adapter: MyApp.ScheduleAdapter}
        ]
      ]

  Runtime options can change only options owned by the AgentServer Plugin
  facet. They do not change the Agent definition or persistence Plugin options.

  Durable delivery uses generation `0` when a saved recurring definition has
  no generation. Local delivery keeps the old untagged Signal behavior for such
  definitions.

  Recurring definitions become durable when `reconcile/2` succeeds. A delayed
  one-shot Signal becomes durable when `schedule/3` succeeds. A process failure
  before either callback succeeds can lose the new schedule. A host that needs
  atomic Agent commits and schedule storage must add an outbox at its storage
  boundary.
  """

  use Jido.Plugin,
    option_keys: [agent_server: [:delivery_adapter, :retry_delay_ms, :time_scale]]

  @impl true
  defdelegate state_spec(opts), to: Jido.Plugin.Scheduler.Agent

  @impl true
  defdelegate directives(opts), to: Jido.Plugin.Scheduler.Agent

  @impl true
  defdelegate reduce(reduction, opts), to: Jido.Plugin.Scheduler.Agent

  @impl true
  def validate_options(opts), do: validate_runtime_options(opts)

  @impl true
  defdelegate dispatch(runtime, directive, context, opts), to: Jido.Plugin.Scheduler.Server

  @impl true
  defdelegate await_ready(runtime, opts), to: Jido.Plugin.Scheduler.Server

  @impl true
  defdelegate child_spec(init), to: Jido.Plugin.Scheduler.Server

  alias Jido.Plugin.Scheduler.{
    Cancel,
    CronRules,
    Cron,
    Occurrence,
    Schedule
  }

  alias Jido.Signal

  @timer_max 4_294_967_295
  @cron_option_keys [:timezone, :generation]

  @typedoc "One Scheduler Plugin option."
  @type option ::
          {:retry_delay_ms, 1..4_294_967_295}
          | {:time_scale, module()}
          | {:delivery_adapter, module()}

  @typedoc "One recurring schedule constructor option."
  @type cron_option ::
          {:timezone, String.t() | nil}
          | {:generation, 0..2_147_483_647 | nil}

  @doc "Creates one delayed Signal Directive."
  @spec schedule(non_neg_integer(), Signal.t()) :: Schedule.t()
  def schedule(delay_ms, signal), do: %Schedule{delay_ms: delay_ms, signal: signal}

  @doc "Creates one recurring Signal Directive."
  @spec cron(term(), String.t(), Signal.t(), [cron_option()]) :: Cron.t()
  def cron(job_id, cron, signal, opts \\ []) do
    validate_cron_options!(opts)

    %Cron{
      job_id: job_id,
      cron: cron,
      signal: signal,
      timezone: Keyword.get(opts, :timezone),
      generation: Keyword.get(opts, :generation)
    }
  end

  @doc "Reads logical occurrence metadata from a recurring tick."
  @spec occurrence(Signal.t()) :: {:ok, Occurrence.t()} | {:error, term()}
  defdelegate occurrence(signal), to: Occurrence, as: :from_signal

  @doc "Returns the next UTC occurrence after one UTC instant."
  @spec next_occurrence(String.t(), String.t(), DateTime.t()) ::
          {:ok, DateTime.t()} | {:error, term()}
  defdelegate next_occurrence(expression, timezone, after_time), to: CronRules

  @doc "Builds one fresh recurring occurrence Signal."
  @spec occurrence_signal(Signal.t(), term(), term(), non_neg_integer() | nil, DateTime.t()) ::
          {:ok, Signal.t()} | {:error, term()}
  defdelegate occurrence_signal(signal, scope, job_id, generation, scheduled_at),
    to: CronRules

  @doc "Creates one recurring schedule cancellation Directive."
  @spec cancel(term()) :: Cancel.t()
  def cancel(job_id), do: %Cancel{job_id: job_id}

  @doc false
  @spec validate_runtime_options(keyword()) ::
          :ok | {:error, Jido.Error.ValidationError.t()}
  def validate_runtime_options(opts) do
    with :ok <- validate_retry_delay(Keyword.fetch(opts, :retry_delay_ms)),
         :ok <- validate_time_scale(Keyword.fetch(opts, :time_scale)),
         :ok <- validate_delivery_adapter(Keyword.fetch(opts, :delivery_adapter)),
         do: :ok
  end

  defp validate_cron_options!(opts) do
    unless Keyword.keyword?(opts) do
      raise ArgumentError, "Scheduler cron options must be a keyword list"
    end

    keys = Keyword.keys(opts)
    duplicate? = Enum.uniq(keys) != keys
    unknown = keys -- @cron_option_keys

    cond do
      :delivery in keys ->
        raise ArgumentError, "Scheduler delivery is not supported"

      duplicate? ->
        raise ArgumentError, "Scheduler cron options must be unique"

      unknown != [] ->
        raise ArgumentError, "Scheduler cron does not accept options #{inspect(unknown)}"

      true ->
        :ok
    end
  end

  defp validate_retry_delay(:error), do: :ok

  defp validate_retry_delay({:ok, value})
       when is_integer(value) and value in 1..@timer_max,
       do: :ok

  defp validate_retry_delay({:ok, value}) do
    invalid_option("Scheduler retry_delay_ms is invalid", %{
      option: :retry_delay_ms,
      value: value,
      range: 1..@timer_max
    })
  end

  defp validate_time_scale(:error), do: :ok

  defp validate_time_scale({:ok, time_scale}) do
    valid? =
      is_atom(time_scale) and not is_nil(time_scale) and Code.ensure_loaded?(time_scale) and
        Enum.all?(SchedEx.TimeScale.behaviour_info(:callbacks), fn {callback, arity} ->
          function_exported?(time_scale, callback, arity)
        end)

    if valid? do
      :ok
    else
      invalid_option("Scheduler time_scale is invalid", %{
        option: :time_scale,
        value: time_scale,
        callbacks: SchedEx.TimeScale.behaviour_info(:callbacks)
      })
    end
  end

  defp validate_delivery_adapter(:error), do: :ok

  defp validate_delivery_adapter({:ok, adapter}) do
    valid? =
      is_atom(adapter) and adapter not in [nil, true, false] and
        Code.ensure_loaded?(adapter) and
        function_exported?(adapter, :reconcile, 2) and
        function_exported?(adapter, :schedule, 3)

    if valid? do
      :ok
    else
      invalid_option("Scheduler delivery_adapter is invalid", %{
        option: :delivery_adapter,
        value: adapter,
        callbacks: [reconcile: 2, schedule: 3]
      })
    end
  end

  defp invalid_option(message, details) do
    {:error, Jido.Error.validation_error(message, kind: :config, details: details)}
  end
end

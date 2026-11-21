defmodule Jido.Plugin.Timer do
  @moduledoc """
  Adds delayed and recurring Signals to an Agent.

  The Plugin owns the `:timer` part of Agent state. This state contains the
  recurring cron and fixed-delay interval definitions. An interval definition
  can be running or paused. Its supervised runtime owns timers and job
  references.

  A delayed Signal from `schedule/2` is a runtime-only one-shot. It is not in
  Agent state or in a checkpoint. A Timer, Agent, or VM restart can discard
  it. Active recurring definitions can restore future timers when Agent state
  is restored. Paused intervals stay paused. Slots that pass while the
  runtime is offline are not replayed.

  Use `every/4` for a stateful fixed-delay interval. The first occurrence waits
  one full interval. The next interval starts after the current occurrence is
  produced. A runtime restart starts a new full interval; it does not restore
  the prior phase.

      directive = Jido.Plugin.Timer.every("review", 1_000, tick)

  A Timer declaration can also start one fixed interval without a control
  Action. Set `:interval` and, when needed, `:signal_type`, `:signal_data`, or
  `:source`. Use this mode instead of the removed `Jido.Plugin.Heartbeat`.

      plugins: [
        {Jido.Plugin.Timer,
         interval: 1_000,
         signal_type: "system.heartbeat",
         signal_data: %{source: :clock}}
      ]

  `pause/1` keeps an interval definition but stops future timer production.
  `resume/1` starts a new future timer. It also advances the
  generation so an application can reject an occurrence delivered under the
  prior activation. `cancel/1` removes either recurring definition kind.

  Pass `generation: integer` (0 through 2,147,483,647) to `cron/4` or
  `every/4` to set logical occurrence metadata. Interval definitions start at
  generation `0` when this option is absent. An implicit interval replacement
  advances its current generation. Retain the committed generation across
  restore. `Jido.Plugin.Timer.Occurrence.from_signal/1` reads the metadata.
  Signal data stays unchanged. Cron definitions remain untagged when generation
  is absent.

      directive = Jido.Plugin.Timer.cron("report", "0 * * * *", tick, generation: 1)

  In the tick Action, read the metadata from `context.signal`:

      {:ok, occurrence} = Jido.Plugin.Timer.Occurrence.from_signal(context.signal)
      occurrence.id

  `:retry_delay_ms` sets the delay after a recurring job cannot start (default
  1,000; positive integer up to 4,294,967,295). A valid finite cron expression
  with no future occurrence is dormant, not failed. It stays in Agent state so
  it can be cancelled or replaced, and it does not prevent other jobs from
  starting during restore.

  The optional Plugin option `:time_scale` accepts a `SchedEx.TimeScale` module
  with `now/1` and `speedup/0` callbacks for controlled time. Its `speedup/0`
  result must be a positive number, and `now/1` must return a `DateTime`. It
  affects cron schedules only. Fixed-delay intervals use wall time. The default
  uses current time. Runtime clock state is not saved in the Agent checkpoint.

  The optional `:delivery_adapter` moves delayed and recurring delivery to an
  external host. The Timer still owns definitions, cron calculation,
  generations, and occurrence metadata. With this option, the AgentServer
  starts no local schedule delivery timers. The adapter receives cron
  definitions through `reconcile/2`. Fixed-delay intervals are not supported
  with an external delivery adapter. The adapter owns persistence, leases,
  delivery, and acknowledgement.

  An application can install one adapter for its AgentServer instances:

      agent_server: [
        plugin_runtime_options: [
          {Jido.Plugin.Timer, delivery_adapter: MyApp.ScheduleAdapter}
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
    option_keys: [
      agent: [:interval, :signal_type, :signal_data, :source],
      agent_server: [:delivery_adapter, :retry_delay_ms, :time_scale]
    ]

  alias Crontab.CronExpression.Parser
  alias Jido.Joi
  alias Jido.Plugin.{Context, Init}

  alias Jido.Plugin.Timer.{
    Cancel,
    CronRules,
    Cron,
    Every,
    Occurrence,
    Pause,
    Resume,
    Runtime,
    Schedule
  }

  alias Jido.Plugin.Timer.Signal.Tick

  alias Jido.Signal

  @timer_max 4_294_967_295
  @default_interval 5_000
  @static_job_id :heartbeat
  @cron_option_keys [:timezone, :generation]
  @every_option_keys [:generation]
  @cron_spec_schema Joi.object(
                      %{
                        cron_expression: Joi.string(),
                        message: Joi.struct(Signal),
                        timezone: Joi.string(),
                        generation:
                          Joi.integer()
                          |> Joi.min(0)
                          |> Joi.max(2_147_483_647)
                          |> Joi.optional()
                      },
                      unrecognized_keys: :error
                    )
  @every_spec_schema Joi.object(
                       %{
                         interval_ms: Joi.integer() |> Joi.min(1) |> Joi.max(@timer_max),
                         message: Joi.struct(Signal),
                         generation: Joi.integer() |> Joi.min(0) |> Joi.max(2_147_483_647),
                         status: Joi.enum([:running, :paused])
                       },
                       unrecognized_keys: :error
                     )
  @state_schema Joi.object(%{
                  cron:
                    Joi.map(Joi.any(), @cron_spec_schema, description: "Recurring cron definitions")
                    |> Joi.refine({CronRules, :validate_state, []})
                    |> Joi.default(%{}),
                  every:
                    Joi.map(Joi.any(), @every_spec_schema, description: "Recurring interval definitions")
                    |> Joi.refine({Every, :validate_state, []})
                    |> Joi.default(%{})
                })
                |> Joi.refine({__MODULE__, :validate_state, []})

  @impl true
  def state_spec(opts) do
    case initial_state(opts) do
      {:ok, state} -> {:timer, Joi.default(@state_schema, state)}
      {:error, reason} -> {:error, static_option_error(reason)}
    end
  end

  @impl true
  def directives(_opts), do: [Schedule, Cron, Every, Pause, Resume, Cancel]

  @impl true
  def reduce(reduction, _opts) do
    state = Map.merge(%{cron: %{}, every: %{}}, reduction.plugin_state)
    apply_directives(state, reduction.directives)
  end

  @impl true
  def validate_options(opts), do: validate_runtime_options(opts)

  @impl true
  def dispatch(runtime, directive, %Context{phase: :directive} = context, opts) do
    GenServer.call(runtime, {:directive, directive, context}, Keyword.get(opts, :timeout, 5_000))
  catch
    :exit, reason -> {:error, {:timer_runtime_unavailable, reason}}
  end

  @impl true
  def await_ready(runtime, opts) do
    GenServer.call(runtime, :await_ready, Keyword.get(opts, :timeout, 5_000))
  catch
    :exit, reason -> {:error, {:timer_runtime_unavailable, reason}}
  end

  @impl true
  def child_spec(%Init{} = init) do
    Supervisor.child_spec({Runtime, init}, id: init.module)
  end

  @typedoc "One Timer Plugin option."
  @type option ::
          {:retry_delay_ms, 1..4_294_967_295}
          | {:time_scale, module()}
          | {:delivery_adapter, module()}
          | {:interval, pos_integer()}
          | {:signal_type, String.t()}
          | {:signal_data, map()}
          | {:source, String.t()}

  @typedoc "One recurring schedule constructor option."
  @type cron_option ::
          {:timezone, String.t() | nil}
          | {:generation, 0..2_147_483_647 | nil}

  @typedoc "One recurring interval constructor option."
  @type every_option :: {:generation, 0..2_147_483_647 | nil}

  @typedoc "Stored lifecycle state for one recurring definition."
  @type status :: %{
          kind: :cron | :every,
          status: :active | :paused,
          generation: 0..2_147_483_647 | nil
        }

  @doc """
  Reads one recurring definition from the full validated Agent state map.

  Returns `{:error, :not_found}` when the Timer Plugin or job is absent.
  `:active` means the stored definition permits Signal production. It does
  not confirm a live timer or successful delivery. A dormant cron definition
  is still active. Paused intervals return `:paused`.

  Cron definitions without an explicit generation return `generation: nil`.
  This function does not change state or contact the runtime. Pass Agent
  state, such as `context.agent_state`, rather than an Agent, PID, or Timer
  state slice. Use `Jido.Plugin.Timer.Occurrence.from_signal/1` to read Signal
  metadata. The application owns job selection and acceptance of queued work.
  """
  @spec status(map(), term()) :: {:ok, status()} | {:error, :not_found}
  def status(agent_state, job_id) when is_map(agent_state) and not is_struct(agent_state) do
    timer = Map.get(agent_state, :timer, %{})

    case Map.fetch(Map.get(timer, :every, %{}), job_id) do
      {:ok, spec} ->
        status = if spec.status == :paused, do: :paused, else: :active
        {:ok, %{kind: :every, status: status, generation: spec.generation}}

      :error ->
        case Map.fetch(Map.get(timer, :cron, %{}), job_id) do
          {:ok, spec} ->
            {:ok, %{kind: :cron, status: :active, generation: Map.get(spec, :generation)}}

          :error ->
            {:error, :not_found}
        end
    end
  end

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

  @doc "Creates one recurring fixed-delay Signal Directive."
  @spec every(term(), pos_integer(), Signal.t(), [every_option()]) :: Every.t()
  def every(job_id, interval_ms, signal, opts \\ []) do
    validate_every_options!(opts)

    %Every{
      job_id: job_id,
      interval_ms: interval_ms,
      signal: signal,
      generation: Keyword.get(opts, :generation)
    }
  end

  @doc false
  @spec static_configuration(keyword()) :: {:ok, map()} | {:error, term()}
  def static_configuration(opts) when is_list(opts) do
    config = %{
      interval: Keyword.get(opts, :interval, @default_interval),
      signal_type: Keyword.get(opts, :signal_type, Tick.type()),
      signal_data: Keyword.get(opts, :signal_data, %{}),
      source: Keyword.get(opts, :source, Tick.default_source())
    }

    with :ok <- validate_static_interval(config.interval),
         :ok <- validate_static_signal_type(config.signal_type),
         :ok <- validate_static_signal_data(config.signal_data),
         :ok <- validate_static_source(config.source) do
      {:ok, config}
    end
  end

  def static_configuration(opts), do: {:error, {:invalid_timer_options, opts}}

  @doc "Returns the next UTC occurrence after one UTC instant."
  @spec next_occurrence(String.t(), String.t(), DateTime.t()) ::
          {:ok, DateTime.t()} | {:error, term()}
  def next_occurrence(expression, timezone, %DateTime{} = after_time)
      when is_binary(expression) and is_binary(timezone) do
    extended? = length(String.split(expression)) > 5

    with {:ok, cron} <- Parser.parse(expression, extended?),
         {:ok, local_after} <- DateTime.shift_zone(after_time, timezone) do
      next_strict(cron, timezone, local_after, after_time)
    end
  rescue
    _exception -> {:error, :invalid_cron_boundary}
  catch
    _kind, _reason -> {:error, :invalid_cron_boundary}
  end

  def next_occurrence(_expression, _timezone, _after_time),
    do: {:error, :invalid_cron_boundary}

  @doc "Builds one fresh recurring occurrence Signal."
  @spec occurrence_signal(Signal.t(), term(), term(), non_neg_integer() | nil, DateTime.t()) ::
          {:ok, Signal.t()} | {:error, term()}
  def occurrence_signal(%Signal{} = signal, scope, job_id, nil, %DateTime{} = scheduled_at),
    do: occurrence_signal(signal, scope, job_id, 0, scheduled_at)

  def occurrence_signal(
        %Signal{} = signal,
        scope,
        job_id,
        generation,
        %DateTime{} = scheduled_at
      )
      when is_integer(generation) and generation in 0..2_147_483_647 do
    with :ok <- CronRules.validate_occurrence_scope(scope),
         :ok <- CronRules.validate_job_id(job_id),
         :ok <- Occurrence.validate_template(signal) do
      Occurrence.attach(fresh_signal(signal), scope, job_id, generation, scheduled_at)
    end
  end

  def occurrence_signal(_signal, _scope, _job_id, _generation, _scheduled_at),
    do: {:error, :invalid_schedule_occurrence}

  @doc "Creates one recurring schedule cancellation Directive."
  @spec cancel(term()) :: Cancel.t()
  def cancel(job_id), do: %Cancel{job_id: job_id}

  @doc "Creates one recurring interval pause Directive."
  @spec pause(term()) :: Pause.t()
  def pause(job_id), do: %Pause{job_id: job_id}

  @doc "Creates one recurring interval resume Directive."
  @spec resume(term()) :: Resume.t()
  def resume(job_id), do: %Resume{job_id: job_id}

  @doc false
  @spec validate_state(map(), keyword()) :: :ok | {:error, String.t()}
  def validate_state(%{cron: cron, every: every}, _opts) do
    cron_ids = Map.keys(cron)

    if Enum.any?(cron_ids, &Map.has_key?(every, &1)),
      do: {:error, "recurring job IDs must be unique across cron and interval definitions"},
      else: :ok
  end

  defp initial_state([]), do: {:ok, %{cron: %{}, every: %{}}}

  defp initial_state(opts) when is_list(opts) do
    with {:ok, config} <- static_configuration(opts),
         {:ok, signal} <-
           Signal.new(config.signal_type, config.signal_data, source: config.source) do
      {:ok,
       %{
         cron: %{},
         every: %{@static_job_id => Every.build_spec(config.interval, signal, 0)}
       }}
    end
  end

  defp initial_state(opts), do: {:error, {:invalid_timer_options, opts}}

  defp static_option_error(reason) do
    Jido.Error.validation_error("Timer static interval options are invalid",
      kind: :config,
      details: %{reason: reason}
    )
  end

  defp validate_static_interval(interval)
       when is_integer(interval) and interval in 1..@timer_max,
       do: :ok

  defp validate_static_interval(interval),
    do: {:error, {:invalid_timer_interval, interval}}

  defp validate_static_signal_type(type) when is_binary(type) and type != "" do
    case Signal.validate_utf8_string(type, []) do
      :ok -> :ok
      _error -> {:error, {:invalid_timer_signal_type, type}}
    end
  end

  defp validate_static_signal_type(type),
    do: {:error, {:invalid_timer_signal_type, type}}

  defp validate_static_signal_data(data) when is_map(data) and not is_struct(data), do: :ok

  defp validate_static_signal_data(data),
    do: {:error, {:invalid_timer_signal_data, data}}

  defp validate_static_source(source) when is_binary(source) and source != "" do
    case Signal.validate_uri_reference(source, []) do
      :ok -> :ok
      _error -> {:error, {:invalid_timer_source, source}}
    end
  end

  defp validate_static_source(source), do: {:error, {:invalid_timer_source, source}}

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
      raise ArgumentError, "Timer cron options must be a keyword list"
    end

    keys = Keyword.keys(opts)
    duplicate? = Enum.uniq(keys) != keys
    unknown = keys -- @cron_option_keys

    cond do
      :delivery in keys ->
        raise ArgumentError, "Timer delivery is not supported"

      duplicate? ->
        raise ArgumentError, "Timer cron options must be unique"

      unknown != [] ->
        raise ArgumentError, "Timer cron does not accept options #{inspect(unknown)}"

      true ->
        :ok
    end
  end

  defp validate_every_options!(opts) do
    unless Keyword.keyword?(opts) do
      raise ArgumentError, "Timer every options must be a keyword list"
    end

    keys = Keyword.keys(opts)
    duplicate? = Enum.uniq(keys) != keys
    unknown = keys -- @every_option_keys

    cond do
      :delivery in keys ->
        raise ArgumentError, "Timer delivery is not supported"

      duplicate? ->
        raise ArgumentError, "Timer every options must be unique"

      unknown != [] ->
        raise ArgumentError, "Timer every does not accept options #{inspect(unknown)}"

      true ->
        :ok
    end
  end

  defp validate_retry_delay(:error), do: :ok

  defp validate_retry_delay({:ok, value})
       when is_integer(value) and value in 1..@timer_max,
       do: :ok

  defp validate_retry_delay({:ok, value}) do
    invalid_option("Timer retry_delay_ms is invalid", %{
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
      invalid_option("Timer time_scale is invalid", %{
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
      invalid_option("Timer delivery_adapter is invalid", %{
        option: :delivery_adapter,
        value: adapter,
        callbacks: [reconcile: 2, schedule: 3]
      })
    end
  end

  defp invalid_option(message, details) do
    {:error, Jido.Error.validation_error(message, kind: :config, details: details)}
  end

  defp apply_directives(state, directives) do
    Enum.reduce_while(directives, {:ok, state}, &apply_directive/2)
  end

  defp apply_directive(%Cron{} = directive, {:ok, state}) do
    spec =
      CronRules.build_spec(
        directive.cron,
        directive.signal,
        directive.timezone,
        directive.generation
      )

    state =
      state
      |> put_in([:cron, directive.job_id], spec)
      |> update_in([:every], &Map.delete(&1, directive.job_id))

    {:cont, {:ok, state}}
  end

  defp apply_directive(%Every{} = directive, {:ok, state}) do
    with {:ok, generation} <- interval_generation(state, directive) do
      spec = Every.build_spec(directive.interval_ms, directive.signal, generation)

      state =
        state
        |> put_in([:every, directive.job_id], spec)
        |> update_in([:cron], &Map.delete(&1, directive.job_id))

      {:cont, {:ok, state}}
    else
      {:error, reason} -> {:halt, {:error, reason}}
    end
  end

  defp apply_directive(%Pause{job_id: job_id}, {:ok, state}) do
    case get_in(state, [:every, job_id]) do
      nil -> {:cont, {:ok, state}}
      _spec -> {:cont, {:ok, put_in(state, [:every, job_id, :status], :paused)}}
    end
  end

  defp apply_directive(%Resume{job_id: job_id}, {:ok, state}) do
    case get_in(state, [:every, job_id]) do
      %{status: :paused} ->
        case advance_generation(state, job_id) do
          {:ok, state} -> {:cont, {:ok, put_in(state, [:every, job_id, :status], :running)}}
          {:error, reason} -> {:halt, {:error, reason}}
        end

      _other ->
        {:cont, {:ok, state}}
    end
  end

  defp apply_directive(%Cancel{job_id: job_id}, {:ok, state}) do
    state =
      state
      |> update_in([:cron], &Map.delete(&1, job_id))
      |> update_in([:every], &Map.delete(&1, job_id))

    {:cont, {:ok, state}}
  end

  defp apply_directive(_other, {:ok, state}), do: {:cont, {:ok, state}}

  defp interval_generation(_state, %Every{generation: generation}) when is_integer(generation),
    do: {:ok, generation}

  defp interval_generation(state, %Every{job_id: job_id}) do
    current = get_in(state, [:every, job_id]) || get_in(state, [:cron, job_id])

    case current && Map.get(current, :generation) do
      nil -> {:ok, 0}
      generation -> next_generation(generation)
    end
  end

  defp advance_generation(state, job_id) do
    spec = get_in(state, [:every, job_id])

    with {:ok, generation} <- next_generation(spec.generation) do
      {:ok, put_in(state, [:every, job_id, :generation], generation)}
    end
  end

  defp next_generation(generation) when generation < 2_147_483_647, do: {:ok, generation + 1}

  defp next_generation(_generation) do
    {:error,
     Jido.Error.validation_error("Timer generation cannot advance",
       kind: :config,
       details: %{generation: 2_147_483_647}
     )}
  end

  defp fresh_signal(%Signal{} = signal) do
    signal
    |> Jido.Signal.Codec.to_map()
    |> Map.delete("id")
    |> Signal.new!()
  end

  defp next_local(cron, timezone, local_after) do
    case Crontab.Scheduler.get_next_run_date(cron, DateTime.to_naive(local_after)) do
      {:ok, naive_next} -> to_utc(cron, timezone, naive_next)
      {:error, _reason} = error -> error
    end
  end

  defp next_strict(cron, timezone, local_after, after_time) do
    with {:ok, next} <- next_local(cron, timezone, local_after) do
      if DateTime.compare(next, after_time) == :gt do
        {:ok, next}
      else
        next_local(cron, timezone, DateTime.add(local_after, 1, :microsecond))
      end
    end
  end

  defp to_utc(cron, timezone, naive_next) do
    case DateTime.from_naive(naive_next, timezone) do
      {:ok, next} -> DateTime.shift_zone(next, "Etc/UTC")
      {:ambiguous, _first, second} -> DateTime.shift_zone(second, "Etc/UTC")
      {:gap, _before, just_after} -> next_local(cron, timezone, just_after)
      {:error, _reason} = error -> error
    end
  end
end

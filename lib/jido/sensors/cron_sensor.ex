defmodule Jido.Sensors.Cron do
  @moduledoc """
  A sensor that emits signals based on cron schedules via Quantum.

  By default, the sensor uses the Quantum scheduler referenced by `:jido_quantum`,
  but you can override the scheduler name by specifying `quantum_ref` in the sensor's
  start options.

  You can also specify a list of cron jobs to be automatically added at startup via
  the `jobs` parameter. Each entry can be:
  - `{<Crontab.CronExpression>, <task>}` -> auto-generated job name
  - `{<job_name>, <Crontab.CronExpression>, <task>}` -> manual job name

  Example Usage:

      {:ok, sensor} =
        Jido.Sensors.Cron.start_link(
          id: "my_cron_sensor",
          target: {:bus, [target: :my_bus, stream: "some_stream"]},
          scheduler: Jido.Scheduler,
          jobs: [
            # Auto-named job
            {~e"* * * * * *"e, :task1},
            # Named job
            {:my_job, ~e"0 */2 * * * *"e, :task2}
          ]
        )

      # Add a new job later
      :ok = Jido.Sensors.Cron.add_job(sensor, :manual_job, ~e"* * * * *"e, :another_task)

      # Remove the job
      :ok = Jido.Sensors.Cron.remove_job(sensor, :manual_job)

      # Run a job immediately
      :ok = Jido.Sensors.Cron.run_job(sensor, :my_job)
  """

  use Jido.Sensor,
    name: "cron_sensor",
    description: "Emits signals based on cron schedules",
    category: :system,
    tags: [:cron, :scheduling],
    vsn: "1.0.0",
    schema: [
      scheduler: [
        type: :atom,
        default: Jido.Scheduler,
        doc: "Reference to the Quantum scheduler module to use"
      ],
      jobs: [
        type: {:list, :any},
        default: [],
        doc: """
        A list of cron jobs to be added at sensor startup. Each entry can be:
          - {cron_expr, task}
          - {name, cron_expr, task}
        """
      ]
    ]

  require Logger

  @impl true
  def mount(opts) do
    state = %{
      id: opts[:id],
      target: opts[:target],
      sensor: %{name: "cron_sensor"},
      config: %{
        scheduler: opts[:scheduler] || Jido.Scheduler,
        jobs: opts[:jobs] || []
      }
    }

    # Add any job specs provided in the config
    Enum.each(state.config.jobs, fn job_spec ->
      case job_spec do
        {schedule, task} ->
          # Auto-generate a unique name
          unique_name = :"auto_job_#{System.unique_integer([:positive])}"
          add_job_now(state, unique_name, schedule, task)

        {name, schedule, task} ->
          add_job_now(state, name, schedule, task)

        other ->
          Logger.warning("Unsupported job specification in Cron :jobs => #{inspect(other)}")
      end
    end)

    {:ok, state}
  end

  @impl true
  def deliver_signal(state) do
    Jido.Signal.new(%{
      source: "#{Map.get(state.sensor, :name)}:#{state.id}",
      type: "cron_sensor_signal",
      data: %{
        scheduler: state.config.scheduler,
        timestamp: DateTime.utc_now()
      }
    })
  end

  @doc """
  Adds a new cron job with the given name, schedule, and task.

  `name` must be an atom.
  `schedule` is a Crontab.CronExpression (supports `~e""` sigil or built manually).
  `task` can be any term you want included in the dispatched signal's data.
  """
  @spec add_job(GenServer.server(), atom(), Crontab.CronExpression.t(), any()) ::
          :ok | {:error, any()}
  def add_job(sensor, name, schedule, task) when is_atom(name) do
    GenServer.call(sensor, {:add_job, name, schedule, task})
  end

  @doc """
  Removes a cron job by name.
  """
  @spec remove_job(GenServer.server(), atom()) :: :ok | {:error, any()}
  def remove_job(sensor, name) when is_atom(name) do
    GenServer.call(sensor, {:remove_job, name})
  end

  @doc """
  Activates a cron job by name.
  """
  @spec activate_job(GenServer.server(), atom()) :: :ok | {:error, any()}
  def activate_job(sensor, name) when is_atom(name) do
    GenServer.call(sensor, {:activate_job, name})
  end

  @doc """
  Deactivates a cron job by name.
  """
  @spec deactivate_job(GenServer.server(), atom()) :: :ok | {:error, any()}
  def deactivate_job(sensor, name) when is_atom(name) do
    GenServer.call(sensor, {:deactivate_job, name})
  end

  @doc """
  Runs a job immediately (outside its normal schedule).
  """
  @spec run_job(GenServer.server(), atom()) :: :ok | {:error, any()}
  def run_job(sensor, name) when is_atom(name) do
    GenServer.call(sensor, {:run_job, name})
  end

  @impl true
  def handle_call({:add_job, name, schedule, task}, _from, state) do
    result = add_job_now(state, name, schedule, task)
    {:reply, result, state}
  end

  def handle_call({:remove_job, name}, _from, state) do
    result = apply(state.config.scheduler, :delete_job, [name])
    {:reply, result, state}
  end

  def handle_call({:activate_job, name}, _from, state) do
    result = apply(state.config.scheduler, :activate_job, [name])
    {:reply, result, state}
  end

  def handle_call({:deactivate_job, name}, _from, state) do
    result = apply(state.config.scheduler, :deactivate_job, [name])
    {:reply, result, state}
  end

  def handle_call({:run_job, name}, _from, state) do
    result = apply(state.config.scheduler, :run_job, [name])
    {:reply, result, state}
  end

  # Internal helper
  defp add_job_now(state, name, schedule, task) do
    job =
      state.config.scheduler.new_job()
      |> Quantum.Job.set_name(name)
      |> Quantum.Job.set_schedule(schedule)
      |> Quantum.Job.set_task(fn ->
        case build_signal(state, name, schedule, task) do
          {:ok, signal} ->
            case Jido.Signal.Dispatch.dispatch(signal, state.target) do
              :ok -> :ok
              other -> other
            end

          {:error, reason} ->
            {:error, reason}
        end
      end)

    # Add the job to the scheduler and return :ok
    case apply(state.config.scheduler, :add_job, [job]) do
      job when is_struct(job, Quantum.Job) -> :ok
      other -> other
    end
  end

  defp build_signal(state, name, schedule, task) do
    now = DateTime.utc_now()

    Jido.Signal.new(%{
      source: "#{Map.get(state.sensor, :name)}:#{state.id}:#{name}",
      type: "cron_trigger",
      data: %{
        name: name,
        schedule: Crontab.CronExpression.Composer.compose(schedule),
        task: task,
        triggered_at: now
      }
    })
  end
end

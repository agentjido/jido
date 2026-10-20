defmodule Jido.Plugin.Scheduler.DSL.Schedule do
  @moduledoc false
  defstruct [:name, :every, :cron, :timezone, :signal, :__spark_metadata__]
end

defmodule Jido.Plugin.Scheduler.DSL do
  @moduledoc "Static schedule authoring. This provider does not start timers."
  alias Crontab.CronExpression.Parser
  alias Jido.Agent.{Data, Error, Route}
  alias Spark.Dsl.Extension, as: E

  @schedule %Spark.Dsl.Entity{
    name: :schedule,
    target: Jido.Plugin.Scheduler.DSL.Schedule,
    args: [:name],
    schema: [
      name: [type: :atom, required: true],
      every: [type: :pos_integer],
      cron: [type: :string],
      timezone: [type: :string],
      signal: [type: :any, required: true]
    ]
  }
  Jido.Plugin.Scheduler.DSL.Schedule = @schedule.target
  @section %Spark.Dsl.Section{name: :schedules, entities: [@schedule]}
  use Jido.Agent.Extension, id: "jido.scheduling", sections: [@section]

  @impl Jido.Agent.Extension
  def lower(dsl, config) do
    schedules = E.get_entities(dsl, [:schedules])

    cond do
      config != %{} and schedules != [] ->
        Error.fail(:ambiguous_config, [], "Use schedule DSL or Plugin data, not both")

      config != %{} ->
        {:ok, config}

      true ->
        lower_schedules(schedules)
    end
  end

  defp lower_schedules(schedules) do
    with {:ok, entries} <- Data.list(schedules, &lower_schedule/1),
         do: {:ok, %{schedules: entries}}
  end

  defp lower_schedule(entry) do
    cond do
      entry.every != nil and (entry.cron != nil or entry.timezone != nil) ->
        Error.fail(
          :schedule_timing,
          [],
          "Use one interval or cron; timezone is valid only with cron"
        )

      entry.every != nil ->
        {:ok,
         %{
           name: entry.name,
           timing: %{kind: :every, milliseconds: entry.every},
           signal: entry.signal
         }}

      entry.cron != nil ->
        {:ok,
         %{
           name: entry.name,
           timing: %{
             kind: :cron,
             expression: entry.cron,
             timezone: entry.timezone || "Etc/UTC"
           },
           signal: entry.signal
         }}

      true ->
        Error.fail(:schedule_timing, [], "Schedule needs an interval or cron")
    end
  end

  @impl Jido.Agent.Extension
  def normalize(value) do
    with {:ok, value} <- Data.fields(value, [:schedules], %{schedules: []}),
         {:ok, schedules} <- Error.at(Data.list(value.schedules, &schedule/1), :schedules),
         :ok <- Data.unique(schedules, & &1.name),
         do: {:ok, %{schedules: schedules}}
  end

  defp schedule(value) do
    with {:ok, value} <- Data.fields(value, [:name, :timing, :signal]),
         :ok <- Data.name(value[:name]),
         {:ok, timing} <- timing(value[:timing]),
         {:ok, signal} <- template(value[:signal]),
         do: {:ok, %{name: value.name, timing: timing, signal: signal}}
  end

  defp timing(%{kind: :every} = value) do
    with {:ok, value} <- Data.fields(value, [:kind, :milliseconds]),
         :ok <- Data.positive(value[:milliseconds]),
         do: {:ok, value}
  end

  defp timing(%{kind: :cron} = value) do
    with {:ok, value} <-
           Data.fields(value, [:kind, :expression, :timezone], %{timezone: "Etc/UTC"}),
         :ok <- Data.nonempty(value[:expression]),
         :ok <- Data.nonempty(value.timezone),
         {:ok, _} <- Parser.parse(value.expression),
         :ok <- timezone(value.timezone) do
      {:ok, value}
    else
      {:error, %Error{}} = error ->
        error

      {:error, reason} ->
        Error.fail(:invalid_cron, [], "Invalid cron expression", %{reason: reason})
    end
  end

  defp timing(_), do: Error.fail(:schedule_timing, [], "Expected interval or cron timing")

  defp timezone(zone) do
    case DateTime.shift_zone(~U[2000-01-01 00:00:00Z], zone) do
      {:ok, _} ->
        :ok

      {:error, reason} ->
        Error.fail(:invalid_timezone, [], "Unknown timezone", %{timezone: zone, reason: reason})
    end
  end

  defp template(value) do
    with {:ok, value} <- Data.fields(value, [:type, :data], %{data: %{}}),
         :ok <- Data.exact(value[:type]),
         :ok <- Data.plain_map(value.data),
         :ok <- Data.static(value.data),
         do: {:ok, value}
  end

  @impl Jido.Agent.Extension
  def verify(data, definition) do
    with {:ok, _} <- Data.list(data.schedules, &verify_schedule(&1, definition)),
         do: :ok
  end

  defp verify_schedule(schedule, definition) do
    case Route.select(definition, schedule.signal.type) do
      {:ok, _} ->
        {:ok, schedule}

      {:error, _} ->
        Error.fail(
          :schedule_input,
          [:schedules, schedule.name],
          "Scheduled Signal has no input route",
          %{type: schedule.signal.type}
        )
    end
  end
end

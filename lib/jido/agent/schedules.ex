defmodule Jido.Agent.Schedules do
  @moduledoc """
  Static schedule declarations on an Agent definition.

  Declarations describe initial Scheduler intent. They do not install jobs,
  seed Plugin state, emit Signals, or start timers at this authoring boundary.
  The later Activation integration must seed only fresh state, retain saved
  cancellations on restore, and enable delivery after readiness. Missed slots
  use `:skip`; Signals use normal turn admission. Runtime schedule changes use
  the Scheduler Plugin contract. An Activation-owned schedule cannot wake a
  stopped Agent.
  """

  alias Jido.Agent.Authoring
  alias Jido.Authoring.Config
  alias Jido.Plugin.Scheduler

  @schema [
    key: [type: :any, required: true],
    every: [type: :pos_integer],
    cron: [type: :string],
    timezone: [type: :string],
    signal: [type: :map, required: true],
    delivery: [type: {:in, [:best_effort, :durable]}, default: :best_effort],
    generation: [type: :non_neg_integer],
    missed: [type: {:in, [:skip]}, default: :skip]
  ]

  @doc false
  def schema, do: @schema

  @doc false
  def validate(values) do
    with {:ok, entries} <- Authoring.traverse_indexed(values, &entry/1),
         :ok <- Authoring.unique_keys(Enum.map(entries, & &1.key), "Schedule keys must be unique"),
         do: {:ok, entries}
  end

  @doc false
  def validate_owner(%{schedules: []}), do: :ok

  def validate_owner(agent) do
    declared? =
      Enum.any?(agent.plugins, fn
        {Scheduler, _options} -> true
        Scheduler -> true
        %{module: Scheduler} -> true
        _ -> false
      end)

    if declared?,
      do: :ok,
      else: Authoring.error("Schedules require Jido.Plugin.Scheduler") |> Authoring.at(:schedules)
  end

  defp entry(value) do
    with {:ok, attrs} <- Authoring.attrs(value),
         :ok <- Config.validate_static_data(attrs) |> static_result(),
         {:ok, entry} <- Authoring.validate_options(attrs, @schema),
         true <- Authoring.key?(entry.key),
         {:ok, entry} <- frequency(entry),
         {:ok, signal} <- signal(entry.signal) |> Authoring.at(:signal),
         :ok <- delivery(entry) do
      {:ok, %{entry | signal: signal}}
    else
      false -> Authoring.error("Schedule key must be a nonempty atom or string")
      error -> error
    end
  end

  defp static_result(:ok), do: :ok

  defp static_result({:error, reason}),
    do: Authoring.error("Schedule data must be static", %{reason: reason})

  defp frequency(%{every: _, cron: _}),
    do: Authoring.error("A schedule accepts every or cron, not both")

  defp frequency(%{every: _, timezone: _}), do: Authoring.error("timezone requires cron")
  defp frequency(%{every: every} = entry) when every <= 4_294_967_295, do: {:ok, entry}

  defp frequency(%{cron: cron} = entry) do
    case Scheduler.validate_cron_spec(cron, nil, Map.get(entry, :timezone)) do
      {:ok, timezone} -> {:ok, Map.put(entry, :timezone, timezone)}
      {:error, reason} -> Authoring.error("Invalid recurring schedule", %{reason: reason})
    end
  end

  defp frequency(_), do: Authoring.error("A schedule requires every or cron")

  defp signal(template) when is_map(template) and not is_struct(template) do
    with :ok <- Authoring.keys(template, [:type, :data]),
         :ok <- Jido.PortableTerm.validate(template, []) |> portable_result() do
      template = Map.put_new(template, :data, %{})

      envelope =
        Map.merge(template, %{
          id: "authoring",
          source: "/jido/schedules",
          time: "2000-01-01T00:00:00Z"
        })

      case Jido.Signal.new(envelope) do
        {:ok, _signal} ->
          {:ok, template}

        {:error, reason} ->
          Authoring.error("Invalid scheduled Signal template", %{reason: reason})
      end
    end
  end

  defp signal(_), do: Authoring.error("Expected a Signal template map")

  defp portable_result(:ok), do: :ok

  defp portable_result({:error, path}),
    do: Authoring.error("Signal template must be portable", %{path: path})

  defp delivery(%{generation: generation}) when generation > 2_147_483_647,
    do: Authoring.error("Schedule generation is too large")

  defp delivery(%{delivery: :durable} = entry) when not is_map_key(entry, :generation),
    do: Authoring.error("Durable delivery requires an explicit generation")

  defp delivery(_), do: :ok
end

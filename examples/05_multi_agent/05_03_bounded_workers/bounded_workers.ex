defmodule Jido.Examples.BoundedWorkers.Start do
  @moduledoc false
  use Jido.Action,
    name: "example_bounded_workers_start",
    schema:
      Zoi.object(%{
        request_id: Zoi.string() |> Zoi.min(1),
        values: Zoi.list(Zoi.integer()),
        limit: Zoi.integer() |> Zoi.min(1) |> Zoi.max(8) |> Zoi.default(2)
      })

  alias Jido.Agent.Directive
  alias Jido.Examples.{BoundedWorkers, Worker}

  def run(input, %{agent_state: state} = context) do
    if state.status == :running or input.request_id in state.seen do
      {:error, Jido.Action.Error.validation_error("request is active or already used")}
    else
      jobs =
        input.values
        |> Enum.with_index()
        |> Enum.map(fn {value, index} ->
          %{id: Integer.to_string(index), value: value}
        end)

      {first, queue} = Enum.split(jobs, input.limit)
      active = first |> Enum.with_index() |> Map.new(fn {job, slot} -> {"slot-#{slot}", job} end)

      next = %{
        state
        | request_id: input.request_id,
          queue: queue,
          active: active,
          slots: Map.keys(active) |> Enum.sort(),
          results: %{},
          total: length(jobs),
          seen: state.seen ++ [input.request_id],
          status: if(jobs == [], do: :completed, else: :running)
      }

      directives =
        Enum.flat_map(Enum.sort(active), fn {tag, job} ->
          [
            Directive.spawn_agent(Map.get(context, :worker, Worker), tag,
              restart: :temporary,
              opts: %{error_policy: :stop_on_error, exec_opts: [timeout: 1_000]}
            ),
            BoundedWorkers.deliver(input.request_id, tag, job)
          ]
        end)

      {:ok, next, directives}
    end
  end
end

defmodule Jido.Examples.BoundedWorkers.Result do
  @moduledoc false
  use Jido.Action,
    name: "example_bounded_workers_result",
    schema:
      Zoi.object(%{
        request_id: Zoi.string(),
        job_id: Zoi.string(),
        tag: Zoi.string(),
        value: Zoi.integer()
      })

  alias Jido.Examples.BoundedWorkers

  def run(input, %{agent_state: state}) do
    if state.status == :running and input.request_id == state.request_id and
         match?(%{id: id} when id == input.job_id, state.active[input.tag]) do
      state = %{state | results: Map.put(state.results, input.job_id, input.value)}

      case state.queue do
        [job | rest] ->
          {:ok, %{state | queue: rest, active: Map.put(state.active, input.tag, job)},
           [BoundedWorkers.deliver(state.request_id, input.tag, job)]}

        [] ->
          active = Map.delete(state.active, input.tag)

          if map_size(active) == 0 do
            {:ok, %{state | active: %{}, status: :completed}, BoundedWorkers.stop_all(state)}
          else
            {:ok, %{state | active: active}}
          end
      end
    else
      {:error, Jido.Action.Error.validation_error("worker result is stale or unrelated")}
    end
  end
end

defmodule Jido.Examples.BoundedWorkers.Cancel do
  @moduledoc false
  use Jido.Action, name: "example_bounded_workers_cancel"

  def run(_, %{agent_state: %{status: :running} = state}),
    do:
      {:ok, %{state | status: :cancelled, queue: [], active: %{}},
       Jido.Examples.BoundedWorkers.stop_all(state)}

  def run(_, _), do: {:error, Jido.Action.Error.validation_error("no worker request is running")}
end

defmodule Jido.Examples.BoundedWorkers.Exit do
  @moduledoc false
  use Jido.Action, name: "example_bounded_workers_exit"

  def run(%{tag: tag}, %{agent_state: %{status: :running} = state}) do
    if tag in state.slots do
      {:ok, %{state | status: :failed, queue: [], active: %{}},
       Jido.Examples.BoundedWorkers.stop_all(state)}
    else
      {:ok, state}
    end
  end

  def run(_, %{agent_state: state}), do: {:ok, state}
end

defmodule Jido.Examples.BoundedWorkers do
  @moduledoc """
  A fixed number of live child Agents process a bounded request. Each result
  assigns the next queued item to the same child. A child loss fails the request
  and stops its siblings. Results remain in input order through their job IDs.
  Partial child commits are not rolled back when the parent request fails.
  """
  use Jido.Agent, name: "example_bounded_workers"

  agent do
    schema Zoi.object(%{
             request_id: Zoi.string() |> Zoi.default(""),
             seen: Zoi.list(Zoi.string()) |> Zoi.default([]),
             status:
               Zoi.enum([:idle, :running, :completed, :failed, :cancelled]) |> Zoi.default(:idle),
             slots: Zoi.list(Zoi.string()) |> Zoi.default([]),
             queue: Zoi.list(Zoi.map()) |> Zoi.default([]),
             active: Zoi.map() |> Zoi.default(%{}),
             results: Zoi.map() |> Zoi.default(%{}),
             total: Zoi.integer() |> Zoi.default(0)
           })
  end

  routes do
    signal_source "/examples/workers"

    route "examples.workers.process", Jido.Examples.BoundedWorkers.Start do
      define :process_values, args: [:request_id, :values, {:optional, :limit}]
    end

    route "examples.workers.cancel", Jido.Examples.BoundedWorkers.Cancel do
      define :cancel
    end

    route "examples.work.result", Jido.Examples.BoundedWorkers.Result
    route "jido.agent.child.started", Jido.Examples.KeepState
    route "jido.agent.child.exit", Jido.Examples.BoundedWorkers.Exit
  end

  @doc "Returns completed values in input order."
  def ordered_results(agent) do
    agent.state.results
    |> Enum.sort_by(fn {id, _} -> String.to_integer(id) end)
    |> Enum.map(&elem(&1, 1))
  end

  @doc false
  def deliver(request_id, tag, job),
    do:
      Jido.Agent.Directive.emit_to_child(
        tag,
        Jido.Examples.Worker.calculate_signal!(request_id, job.id, tag, job.value)
      )

  @doc false
  def stop_all(state), do: Enum.map(state.slots, &Jido.Agent.Directive.stop_child/1)
end

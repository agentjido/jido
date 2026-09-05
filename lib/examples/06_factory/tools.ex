defmodule Jido.Examples.Factory.Tools do
  @moduledoc "ReqLLM tools send typed Signals to a factory. Each call waits only for its command turn."
  alias Jido.Examples.Factory.{Inspection, Protocol}

  @doc false
  def definitions(jido, factory_id, request_id, context) do
    [
      tool(
        "submit_work",
        "Submit one explicit goal. For multiple workshop jobs or generic demo jobs, use submit_jobs once instead. Completion arrives later.",
        Zoi.object(%{"goal" => Protocol.goal_schema()}),
        fn input ->
          command(jido, factory_id, :submit, request_id, "", input["goal"], context)
        end
      ),
      tool(
        "submit_jobs",
        "Queue 1 to 20 workshop jobs in one batch. For 'add 3 jobs' use count 3 and goals []. Empty goals creates numbered demo jobs. If goals are supplied, provide exactly count nonblank goals. This tool is only for workshop mode.",
        Zoi.object(%{
          "count" => Zoi.integer() |> Zoi.min(1) |> Zoi.max(20),
          "goals" => Zoi.list(Protocol.goal_schema()) |> Zoi.max(20) |> Zoi.default([])
        }),
        fn input ->
          goals =
            if input["goals"] == [],
              do: Enum.map(1..input["count"], &"Demonstration job #{&1}"),
              else: input["goals"]

          if length(goals) == input["count"],
            do: submit_jobs(jido, factory_id, request_id, goals),
            else:
              Protocol.invalid(
                "Provide exactly count goals, or an empty list for numbered demo jobs"
              )
        end
      ),
      tool(
        "factory_status",
        "Inspect current jobs, results, queue order, active work, capacity, and scheduler checks.",
        Zoi.object(%{}),
        fn _ -> command(jido, factory_id, :status, request_id, "", "", context) end
      ),
      tool(
        "factory_job",
        "Inspect one job by exact ID: goal, status, progress, result, and queue position.",
        Zoi.object(%{"job_id" => Zoi.string() |> Zoi.min(1)}),
        fn input -> inspect_factory(jido, factory_id, :job, input["job_id"]) end
      ),
      tool(
        "factory_events",
        "Read the last 100 factory events. Use an empty job_id for all jobs, or an exact ID to filter.",
        Zoi.object(%{"job_id" => Zoi.string()}),
        fn input -> inspect_factory(jido, factory_id, :events, input["job_id"]) end
      )
      | Enum.map([:pause, :resume, :cancel], fn operation ->
          tool(
            "#{operation}_work",
            "#{operation} a job by its exact ID.",
            Zoi.object(%{"job_id" => Zoi.string() |> Zoi.min(1)}),
            fn input ->
              command(jido, factory_id, operation, request_id, input["job_id"], "", context)
            end
          )
        end)
    ]
  end

  defp tool(name, description, schema, callback) do
    ReqLLM.tool(
      name: name,
      description: description,
      parameter_schema: Zoi.to_json_schema(schema),
      callback: fn input ->
        case Zoi.parse(schema, input) do
          {:ok, parsed} ->
            callback.(parsed)

          {:error, errors} ->
            detail =
              Enum.map_join(errors, "; ", fn error ->
                "#{Enum.join(error.path, ".")}: #{error.message}"
              end)

            Protocol.invalid("Invalid #{name} arguments: #{detail}")
        end
      end
    )
  end

  @doc "Queues a whole batch in one Agent commit. Repeating the batch returns the same jobs."
  def submit_jobs(jido, factory_id, request_id, goals) do
    with {:ok, data} <-
           Zoi.parse(Protocol.batch_schema(), %{request_id: request_id, goals: goals}),
         pid when is_pid(pid) <- Jido.whereis_agent(jido, factory_id),
         :ok <- workshop_only(pid),
         {:ok, agent} <-
           Jido.AgentServer.call(
             pid,
             Jido.Signal.new!("factory.submit_jobs", data, source: "/conversation/tool")
           ) do
      ids = agent.state.batches[request_id].job_ids
      {:ok, %{job_ids: ids, jobs: Enum.map(ids, &Map.fetch!(agent.state.jobs, &1))}}
    else
      nil -> {:error, :factory_unavailable}
      {:error, reason} -> {:error, reason}
    end
  catch
    :exit, _ -> {:error, :factory_unavailable}
  end

  defp workshop_only(pid) do
    case Jido.AgentServer.call(
           pid,
           Jido.Signal.new!("factory.command", %{operation: :status, request_id: "batch-check"},
             source: "/conversation/tool"
           )
         ) do
      {:ok, %{state: %{queue: _}}} -> :ok
      {:ok, _} -> Protocol.invalid("Batch submission is only available in workshop mode")
      {:error, reason} -> {:error, reason}
    end
  end

  @doc "Sends a factory command. A duplicate submit returns the same job; a changed goal is rejected."
  def command(jido, factory_id, operation, request_id, job_id, goal, context \\ %{}) do
    data = %{operation: operation, request_id: request_id, job_id: job_id, goal: goal}

    with {:ok, data} <- Zoi.parse(Protocol.command_schema(), data),
         pid when is_pid(pid) <- Jido.whereis_agent(jido, factory_id),
         {:ok, agent} <-
           Jido.AgentServer.call(
             pid,
             Jido.Signal.new!("factory.command", data, source: "/conversation/tool"),
             context: context
           ) do
      if operation == :submit do
        {:ok, Map.fetch!(agent.state.jobs, request_id)}
      else
        {:ok, Inspection.overview(agent.state)}
      end
    else
      nil -> {:error, :factory_unavailable}
      {:error, reason} -> {:error, reason}
    end
  catch
    :exit, _ -> {:error, :factory_unavailable}
  end

  @doc "Reads job or event details through the factory Signal mailbox."
  def inspect_factory(jido, factory_id, view, job_id \\ "") do
    with pid when is_pid(pid) <- Jido.whereis_agent(jido, factory_id),
         {:ok, agent} <-
           Jido.AgentServer.call(
             pid,
             Jido.Signal.new!("factory.inspect", %{view: view, job_id: job_id},
               source: "/conversation/tool"
             )
           ) do
      {:ok, Inspection.view(agent.state, view, job_id)}
    else
      nil -> {:error, :factory_unavailable}
      {:error, reason} -> {:error, reason}
    end
  catch
    :exit, _ -> {:error, :factory_unavailable}
  end
end

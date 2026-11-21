defmodule Jido.Examples.Collaboration.ManagerPool.Worker do
  use Jido.Agent, name: "example_manager_pool_worker"

  state do
    schema Jido.Joi.object(%{completed: Jido.Joi.list(Jido.Joi.string()) |> Jido.Joi.default([])})
  end

  routes do
    signal_source "/examples/collaboration/worker"

    route "examples.collaboration.pool.execute", as: :execute do
      action input,
        schema:
          Jido.Joi.object(%{
            task_id: Jido.Joi.string(),
            value: Jido.Joi.integer(),
            fail: Jido.Joi.boolean()
          }),
        output_schema:
          Jido.Joi.object(%{
            state: Jido.Joi.map(),
            reply: Jido.Joi.map()
          }),
        context: context do
        if input.fail do
          {:error, Jido.Error.execution_error("injected worker failure")}
        else
          {:ok,
           %{
             state: %{completed: context.agent_state.completed ++ [input.task_id]},
             reply: %{task_id: input.task_id, status: :completed, value: input.value * 2}
           }}
        end
      end

      state(from: output(:state))
      reply("examples.collaboration.pool.completed", from: output(:reply))
    end
  end
end

defmodule Jido.Examples.Collaboration.ManagerPool.Manager do
  use Jido.Agent, name: "example_manager_pool_manager"

  state do
    schema Jido.Joi.object(%{
             mission_id: Jido.Joi.string() |> Jido.Joi.default(""),
             expected: Jido.Joi.list(Jido.Joi.string()) |> Jido.Joi.default([]),
             results: Jido.Joi.list(Jido.Joi.map()) |> Jido.Joi.default([])
           })
  end

  routes do
    signal_source "/examples/collaboration/manager"

    route "examples.collaboration.pool.started", as: :start do
      action input,
        schema:
          Jido.Joi.object(%{
            mission_id: Jido.Joi.string(),
            task_ids: Jido.Joi.list(Jido.Joi.string())
          }),
        context: context do
        {:ok, %{context.agent_state | mission_id: input.mission_id, expected: input.task_ids, results: []}}
      end
    end

    route "examples.collaboration.pool.result", as: :collect do
      action input,
        schema:
          Jido.Joi.object(%{
            mission_id: Jido.Joi.string(),
            task_id: Jido.Joi.string(),
            status: Jido.Joi.enum([:completed, :failed]),
            value: Jido.Joi.integer() |> Jido.Joi.nullable()
          }),
        context: context do
        state = context.agent_state
        duplicate? = Enum.any?(state.results, &(&1.task_id == input.task_id))

        cond do
          state.mission_id != input.mission_id ->
            {:error, Jido.Error.validation_error("worker result is unrelated")}

          duplicate? ->
            {:ok, state}

          true ->
            {:ok, %{state | results: Enum.sort_by(state.results ++ [input], & &1.task_id)}}
        end
      end
    end
  end
end

defmodule Jido.Examples.Collaboration.ManagerPool do
  alias Jido.Examples.Collaboration.ManagerPool.{Manager, Worker}

  def run(jido, manager_address, worker_addresses, mission_id, tasks) do
    task_ids = Enum.map(tasks, & &1.task_id)

    with {:ok, _turn} <-
           Jido.call(jido, manager_address, Manager.start_signal!(%{mission_id: mission_id, task_ids: task_ids})) do
      results =
        worker_addresses
        |> Enum.zip(tasks)
        |> Task.async_stream(
          fn {worker_address, task} -> run_worker(jido, worker_address, task) end,
          ordered: true,
          max_concurrency: length(worker_addresses),
          timeout: 1_000
        )
        |> Enum.map(fn {:ok, result} -> result end)

      Enum.each(results, fn result ->
        signal = Manager.collect_signal!(Map.put(result, :mission_id, mission_id))
        {:ok, _turn} = Jido.call(jido, manager_address, signal)
      end)

      {:ok, manager} = Jido.activate_agent(jido, manager_address)
      {:ok, Jido.AgentServer.snapshot(manager).agent.state}
    end
  end

  defp run_worker(jido, worker_address, task) do
    signal = Worker.execute_signal!(task)

    case Jido.call(jido, worker_address, signal) do
      {:ok, %Jido.AgentServer.TurnResult{status: :committed, reply: reply}}
      when not is_nil(reply) ->
        reply.data

      {:ok, %Jido.AgentServer.TurnResult{}} ->
        %{task_id: task.task_id, status: :failed, value: nil}

      {:error, _reason} ->
        %{task_id: task.task_id, status: :failed, value: nil}
    end
  end
end

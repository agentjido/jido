defmodule Jido.Examples.Factory.FlowFactory.Mission do
  @moduledoc "Owns one mission and its workers while a Plugin runs the Flow after commit."
  use Jido.Agent, name: "flow_factory_mission"

  alias Jido.Examples.Factory.FlowFactory.{Contract, Runner}

  agent do
    schema Zoi.object(%{
             status:
               Zoi.enum([:idle, :running, :completed, :failed, :cancelled]) |> Zoi.default(:idle),
             goal: Zoi.string() |> Zoi.default(""),
             security: Zoi.boolean() |> Zoi.default(true),
             assignments: Zoi.map() |> Zoi.default(%{}),
             artifacts: Zoi.map() |> Zoi.default(%{}),
             events: Zoi.list(Zoi.map()) |> Zoi.default([]),
             output: Zoi.map() |> Zoi.default(%{}),
             error: Zoi.string() |> Zoi.default("")
           })

    plugin Runner
  end

  routes do
    signal_source "/examples/factory/flow"

    route "examples.factory.flow.start" do
      action input,
        schema:
          Zoi.object(%{
            goal: Zoi.string() |> Zoi.min(1) |> Zoi.max(20_000),
            security: Zoi.boolean() |> Zoi.default(true)
          }),
        context: context do
        Jido.Examples.Factory.FlowFactory.Mission.State.start(input, context)
      end

      define :start, args: [:goal]
    end

    route "examples.factory.flow.progress" do
      action input,
        schema:
          Zoi.object(%{
            mission_id: Zoi.string(),
            assignment_id: Zoi.string(),
            role: Zoi.enum(Contract.roles()),
            revision: Zoi.integer() |> Zoi.min(0) |> Zoi.max(2),
            status: Zoi.enum([:started, :completed]),
            artifact: Zoi.map()
          }),
        context: context do
        Jido.Examples.Factory.FlowFactory.Mission.State.progress(input, context)
      end
    end

    route "examples.factory.flow.finished" do
      action input,
        schema:
          Zoi.object(%{
            mission_id: Zoi.string(),
            status: Zoi.enum([:completed, :failed]),
            output: Zoi.map(),
            error: Zoi.string()
          }),
        context: context do
        Jido.Examples.Factory.FlowFactory.Mission.State.finish(input, context)
      end
    end

    route "examples.factory.flow.cancel" do
      action _input, context: context do
        Jido.Examples.Factory.FlowFactory.Mission.State.cancel(context.agent_state)
      end

      define :cancel
    end

    route "jido.agent.child.exit" do
      action input, context: context do
        Jido.Examples.Factory.FlowFactory.Mission.State.child_exit(input, context.agent_state)
      end
    end

    route "jido.agent.child.started", Jido.Examples.Support.KeepState
  end
end

defmodule Jido.Examples.Factory.FlowFactory.Mission.State do
  @moduledoc false

  alias Jido.Agent.Directive
  alias Jido.Examples.Factory.FlowFactory.{Cancel, Contract, Run, Worker}

  def start(input, %{agent_state: %{status: :idle} = state, agent_id: id}) do
    if String.trim(input.goal) == "" do
      Contract.invalid("Supply a nonblank goal")
    else
      workers =
        Enum.map(Contract.roles(), fn role ->
          Directive.spawn_child(Worker, role,
            restart: :temporary,
            opts: %{initial_state: %{role: role}, exec_opts: [timeout: 50_000]}
          )
        end)

      intent = %Run{mission_id: id, goal: input.goal, security: input.security}

      {:ok, %{state | status: :running, goal: input.goal, security: input.security},
       workers ++ [intent]}
    end
  end

  def start(_, _), do: Contract.invalid("Each Mission Agent accepts one mission")

  def progress(%{mission_id: id} = input, %{
        agent_id: id,
        agent_state: %{status: :running} = state
      }) do
    if input.assignment_id == Contract.assignment_id(input),
      do: record(input, state),
      else: Contract.invalid("Assignment identity is invalid")
  end

  def progress(_, _), do: Contract.invalid("Progress is for an inactive mission")

  def finish(%{mission_id: id} = input, %{
        agent_id: id,
        agent_state: %{status: :running} = state
      }) do
    if input.status == :failed or valid_output?(input.output, state, id) do
      next = %{state | status: input.status, output: input.output, error: input.error}
      {:ok, next, cleanup()}
    else
      Contract.invalid("Flow output is not an accepted, recorded artifact")
    end
  end

  def finish(_, _), do: Contract.invalid("Flow result is for an inactive mission")

  def cancel(%{status: :running} = state),
    do: {:ok, %{state | status: :cancelled}, cleanup()}

  def cancel(_), do: Contract.invalid("Mission is not running")

  def child_exit(%{tag: tag}, %{status: :running} = state) do
    if tag in Contract.roles(),
      do: {:ok, %{state | status: :failed, error: "Worker #{tag} exited"}, cleanup()},
      else: {:ok, state}
  end

  def child_exit(_, state), do: {:ok, state}

  defp cleanup,
    do: [%Cancel{} | Enum.map(Contract.roles(), &Jido.Agent.Directive.stop_child/1)]

  defp record(%{status: :started} = input, state) do
    if Map.has_key?(state.assignments, input.assignment_id) do
      Contract.invalid("Assignment has already started")
    else
      {:ok, append(state, input)}
    end
  end

  defp record(input, state) do
    with :started <- state.assignments[input.assignment_id],
         {:ok, artifact} <- Zoi.parse(Contract.artifact_schema(), input.artifact),
         true <- artifact.id == input.assignment_id and artifact.mission_id == input.mission_id,
         true <- artifact.role == input.role and artifact.revision == input.revision do
      {:ok, %{append(state, input) | artifacts: Map.put(state.artifacts, artifact.id, artifact)}}
    else
      _ -> Contract.invalid("Artifact does not match a pending assignment")
    end
  end

  defp append(state, input) do
    event = Map.drop(input, [:artifact]) |> Map.put(:sequence, length(state.events) + 1)

    %{
      state
      | events: state.events ++ [event],
        assignments: Map.put(state.assignments, input.assignment_id, input.status)
    }
  end

  defp valid_output?(output, state, id) do
    with {:ok, output} <- Zoi.parse(Contract.output_schema(), output),
         mission = output.mission,
         true <- mission.mission_id == id and mission.goal == state.goal,
         true <- mission.accepted and mission.security == state.security,
         true <- mission.revision == output.repairs do
      recorded?(state, mission.package, "integration", mission.revision) and
        recorded?(state, output.handoff, "delivery", mission.revision) and
        accepted_review?(state, mission.review[:quality], "quality", mission.revision) and
        (not state.security or
           accepted_review?(state, mission.review[:security], "security", mission.revision))
    else
      _ -> false
    end
  end

  defp recorded?(state, %{id: id, role: role, revision: revision} = artifact, role, revision),
    do: state.artifacts[id] == artifact

  defp recorded?(_, _, _, _), do: false

  defp accepted_review?(state, %{verdict: :accepted} = review, role, revision),
    do: recorded?(state, review, role, revision)

  defp accepted_review?(_, _, _, _), do: false
end

defmodule Jido.Examples.Factory.FlowFactory do
  @moduledoc "Starts a software proposal mission with nine real worker Agents and one coordinating Flow."
  alias Jido.Examples.Factory.FlowFactory.Mission

  def start(jido, goal, opts \\ []) do
    with {:ok, pid} <-
           Jido.start_agent(jido, Mission, id: Keyword.get(opts, :id, Jido.Signal.ID.generate!())) do
      case Mission.start(pid, goal,
             input: %{security: Keyword.get(opts, :security, true)},
             context: Keyword.get(opts, :context, %{})
           ) do
        {:ok, _} ->
          {:ok, pid}

        error ->
          Jido.stop_agent(jido, pid)
          error
      end
    end
  end

  def status(pid), do: Jido.AgentServer.snapshot(pid).agent.state
  def cancel(pid), do: Mission.cancel(pid)
end

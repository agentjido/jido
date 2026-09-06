defmodule Jido.Examples.Factory.FlowFactory.Start do
  @moduledoc false
  alias Jido.Examples.Factory.FlowFactory.{Contract, Run, Worker}
  alias Jido.Agent.Directive

  use Jido.Action,
    name: "flow_factory_start",
    schema:
      Zoi.object(%{
        goal: Zoi.string() |> Zoi.min(1) |> Zoi.max(20_000),
        security: Zoi.boolean() |> Zoi.default(true)
      })

  def run(input, %{agent_state: %{status: :idle} = state, agent_id: id}) do
    if String.trim(input.goal) == "" do
      Contract.invalid("Supply a nonblank goal")
    else
      workers =
        Enum.map(Contract.roles(), fn role ->
          Directive.spawn_agent(Worker, role,
            restart: :temporary,
            opts: %{initial_state: %{role: role}, exec_opts: [timeout: 50_000]}
          )
        end)

      intent = %Run{mission_id: id, goal: input.goal, security: input.security}

      {:ok, %{state | status: :running, goal: input.goal, security: input.security},
       workers ++ [intent]}
    end
  end

  def run(_, _), do: Contract.invalid("Each Mission Agent accepts one mission")
end

defmodule Jido.Examples.Factory.FlowFactory.Progress do
  @moduledoc false
  alias Jido.Examples.Factory.FlowFactory.Contract

  use Jido.Action,
    name: "flow_factory_progress",
    schema:
      Zoi.object(%{
        mission_id: Zoi.string(),
        assignment_id: Zoi.string(),
        role: Zoi.enum(Contract.roles()),
        revision: Zoi.integer() |> Zoi.min(0) |> Zoi.max(2),
        status: Zoi.enum([:started, :completed]),
        artifact: Zoi.map()
      })

  def run(%{mission_id: id} = input, %{agent_id: id, agent_state: %{status: :running} = state}) do
    if input.assignment_id == Contract.assignment_id(input),
      do: record(input, state),
      else: Contract.invalid("Assignment identity is invalid")
  end

  def run(_, _), do: Contract.invalid("Progress is for an inactive mission")

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
end

defmodule Jido.Examples.Factory.FlowFactory.Finish do
  @moduledoc false
  alias Jido.Examples.Factory.FlowFactory.{Contract, Mission}

  use Jido.Action,
    name: "flow_factory_finish",
    schema:
      Zoi.object(%{
        mission_id: Zoi.string(),
        status: Zoi.enum([:completed, :failed]),
        output: Zoi.map(),
        error: Zoi.string()
      })

  def run(%{mission_id: id} = input, %{agent_id: id, agent_state: %{status: :running} = state}) do
    if input.status == :failed or valid_output?(input.output, state, id) do
      next = %{state | status: input.status, output: input.output, error: input.error}
      {:ok, next, Mission.cleanup()}
    else
      Contract.invalid("Flow output is not an accepted, recorded artifact")
    end
  end

  def run(_, _), do: Contract.invalid("Flow result is for an inactive mission")

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

defmodule Jido.Examples.Factory.FlowFactory.Mission do
  @moduledoc "Owns one mission and its workers while a Plugin runs the Flow after commit."
  alias Jido.Examples.Factory.FlowFactory.{Cancel, Contract, Runner}
  use Jido.Agent, name: "flow_factory_mission"

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

    route "factory.flow.start", Jido.Examples.Factory.FlowFactory.Start do
      define :start, args: [:goal]
    end

    route "factory.flow.progress", Jido.Examples.Factory.FlowFactory.Progress
    route "factory.flow.finished", Jido.Examples.Factory.FlowFactory.Finish

    route "factory.flow.cancel" do
      action _input, name: "flow_factory_cancel", context: context do
        Jido.Examples.Factory.FlowFactory.Mission.cancel_state(context.agent_state)
      end

      define :cancel
    end

    route "jido.agent.child.exit" do
      action input, name: "flow_factory_child_exit", context: context do
        Jido.Examples.Factory.FlowFactory.Mission.child_exit(input, context.agent_state)
      end
    end

    route "jido.agent.child.started", Jido.Examples.KeepState
  end

  @doc false
  def cleanup, do: [%Cancel{} | Enum.map(Contract.roles(), &Jido.Agent.Directive.stop_child/1)]

  @doc false
  def cancel_state(%{status: :running} = state),
    do: {:ok, %{state | status: :cancelled}, cleanup()}

  def cancel_state(_), do: Contract.invalid("Mission is not running")

  @doc false
  def child_exit(%{tag: tag}, %{status: :running} = state) do
    if tag in Contract.roles(),
      do: {:ok, %{state | status: :failed, error: "Worker #{tag} exited"}, cleanup()},
      else: {:ok, state}
  end

  def child_exit(_, state), do: {:ok, state}
end

defmodule Jido.Examples.Factory.FlowFactory do
  @moduledoc "Starts a software proposal mission with nine real worker Agents and one coordinating Flow."
  alias Jido.Examples.Factory.FlowFactory.Mission

  def start(jido, goal, opts \\ []) do
    with {:ok, pid} <-
           Jido.start_agent(jido, Mission, id: Keyword.get(opts, :id, Jido.ID.uuid7())) do
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

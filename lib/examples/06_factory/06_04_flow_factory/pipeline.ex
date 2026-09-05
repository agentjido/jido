defmodule Jido.Examples.Factory.FlowFactory.AskWorker do
  @moduledoc "A Flow Action sends a Signal to a worker and returns its committed artifact."
  alias Jido.AgentServer, as: Server
  alias Jido.Examples.Factory.FlowFactory.Contract
  use Jido.Action, name: "flow_factory_ask", schema: Contract.assignment_schema()

  def run(input, context) do
    with :ok <- progress(input, :started, %{}, context),
         {:ok, worker} <- worker(input.role, context),
         {:ok, agent} <-
           Server.call(
             worker,
             Jido.Signal.new!("factory.flow.work", input, source: "/factory/flow"),
             context: context,
             timeout: 60_000
           ),
         {:ok, artifact} <- artifact(agent, input),
         :ok <- progress(input, :completed, artifact, context) do
      {:ok, artifact}
    end
  catch
    :exit, _ ->
      {:error, Jido.Action.Error.execution_error("Worker or mission became unavailable")}
  end

  defp worker(role, context) do
    case Jido.whereis_agent(context.factory_jido, "#{context.mission_id}/#{role}") do
      nil -> {:error, Jido.Action.Error.execution_error("Worker is unavailable", role: role)}
      pid -> {:ok, pid}
    end
  end

  defp artifact(agent, input) do
    artifact = agent.state.artifacts[Contract.assignment_id(input)]

    with {:ok, parsed} <- Zoi.parse(Contract.artifact_schema(), artifact),
         true <- parsed.input_hash == Contract.input_hash(input),
         true <- parsed.id == Contract.assignment_id(input),
         true <- parsed.mission_id == input.mission_id,
         true <- parsed.role == input.role and parsed.revision == input.revision do
      {:ok, parsed}
    else
      _ -> Contract.invalid("Worker result does not match the assignment")
    end
  end

  defp progress(input, status, artifact, context) do
    signal =
      Jido.Signal.new!(
        "factory.flow.progress",
        %{
          mission_id: input.mission_id,
          assignment_id: Contract.assignment_id(input),
          role: input.role,
          revision: input.revision,
          status: status,
          artifact: artifact
        },
        source: "/factory/flow"
      )

    GenServer.call(context.progress_sink, {:progress, signal})
  end
end

defmodule Jido.Examples.Factory.FlowFactory.Discovery do
  @moduledoc "Two independent worker Agents establish the shared input contract."
  alias Jido.Examples.Factory.FlowFactory.AskWorker
  use Jido.Flow, name: "flow_factory_discovery"

  flow do
    step "research",
      action: AskWorker,
      params: %{
        mission_id: input(:mission_id),
        goal: input(:goal),
        role: "research",
        revision: 0,
        inputs: %{}
      }

    step "design",
      action: AskWorker,
      params: %{
        mission_id: input(:mission_id),
        goal: input(:goal),
        role: "design",
        revision: 0,
        inputs: %{}
      }

    output %{research: result("research"), design: result("design")}
  end
end

defmodule Jido.Examples.Factory.FlowFactory.SkipSecurity do
  @moduledoc false
  use Jido.Action, name: "flow_factory_skip_security"

  def run(_, _),
    do:
      {:ok,
       %{
         verdict: :accepted,
         findings: [],
         skipped: true,
         text: "Security review was not requested."
       }}
end

defmodule Jido.Examples.Factory.FlowFactory.Review do
  @moduledoc "Quality and optional security review run independently before a join."
  alias Jido.Examples.Factory.FlowFactory.{AskWorker, SkipSecurity}
  use Jido.Flow, name: "flow_factory_review"

  flow do
    step "quality",
      action: AskWorker,
      params: %{
        mission_id: input(:mission_id),
        goal: input(:goal),
        role: "quality",
        revision: input(:revision),
        inputs: input(:bundle)
      }

    choice "security" do
      option "required",
        condition: input(:security) == true,
        action: AskWorker,
        params: %{
          mission_id: input(:mission_id),
          goal: input(:goal),
          role: "security",
          revision: input(:revision),
          inputs: input(:bundle)
        }

      otherwise action: SkipSecurity, params: %{}
    end

    step "verdict", [quality <- result("quality"), security <- result("security")] do
      {:ok,
       %{
         accepted: quality.verdict == :accepted and security.verdict == :accepted,
         findings: quality.findings ++ security.findings,
         quality: quality,
         security: security
       }}
    end

    output result("verdict")
  end
end

defmodule Jido.Examples.Factory.FlowFactory.Cycle do
  @moduledoc "An ordered Map builds three artifacts, then integration and parallel reviews run."
  alias Jido.Examples.Factory.FlowFactory.{AskWorker, Contract, Review}
  use Jido.Flow, name: "flow_factory_cycle", output_schema: Contract.cycle_schema()

  flow do
    map "components",
      collection: value(["api", "ui", "test"]),
      action: AskWorker,
      params: %{
        mission_id: input(:mission_id),
        goal: input(:goal),
        role: item(),
        revision: input(:revision),
        inputs: %{
          discovery: input(:discovery),
          findings: input(:findings),
          previous_package: input(:previous_package)
        }
      }

    step "integrate",
      action: AskWorker,
      params: %{
        mission_id: input(:mission_id),
        goal: input(:goal),
        role: "integration",
        revision: input(:revision),
        inputs: %{
          discovery: input(:discovery),
          components: result("components")
        }
      }

    step "review",
      action: Review,
      params: %{
        mission_id: input(:mission_id),
        goal: input(:goal),
        revision: input(:revision),
        security: input(:security),
        bundle: %{
          discovery: input(:discovery),
          components: result("components"),
          package: result("integrate")
        }
      }

    output %{
      mission_id: input(:mission_id),
      goal: input(:goal),
      revision: input(:revision),
      security: input(:security),
      discovery: input(:discovery),
      components: result("components"),
      package: result("integrate"),
      review: result("review"),
      accepted: result("review", :accepted)
    }
  end
end

defmodule Jido.Examples.Factory.FlowFactory.Repair do
  @moduledoc "A bounded Iterate body runs the next build/review Flow with actual findings."
  alias Jido.Examples.Factory.FlowFactory.{Contract, Cycle}
  use Jido.Action, name: "flow_factory_repair", schema: Contract.cycle_schema()

  def run(current, context) do
    params = %{
      mission_id: current.mission_id,
      goal: current.goal,
      revision: current.revision + 1,
      security: current.security,
      discovery: current.discovery,
      findings: current.review.findings,
      previous_package: current.package
    }

    # Iterate expects a completed body result. The nested run uses the remaining mission time.
    Jido.Exec.run(Cycle, params, context,
      task_supervisor: Jido.task_supervisor_name(context.factory_jido),
      max_concurrency: 3,
      timeout: max(context.flow_deadline - System.monotonic_time(:millisecond), 0)
    )
  end
end

defmodule Jido.Examples.Factory.FlowFactory.Pipeline do
  @moduledoc "A complete software proposal: parallel discovery, Map, nested review, bounded repair, and handoff."
  alias Jido.Examples.Factory.FlowFactory.{AskWorker, Contract, Cycle, Discovery, Repair}

  use Jido.Flow,
    name: "flow_factory_pipeline",
    output_schema: Contract.output_schema(),
    schema:
      Zoi.object(%{
        mission_id: Zoi.string() |> Zoi.min(1),
        goal: Zoi.string() |> Zoi.min(1) |> Zoi.max(20_000),
        security: Zoi.boolean()
      })

  flow do
    step "discovery", action: Discovery, params: input()

    step "first_build",
      action: Cycle,
      params: %{
        mission_id: input(:mission_id),
        goal: input(:goal),
        security: input(:security),
        revision: 0,
        discovery: result("discovery"),
        findings: value([]),
        previous_package: %{}
      }

    iterate "repair" do
      state Contract.cycle_schema(), initial: result("first_build")
      action Repair
      params state()
      update body_result()
      while state(:accepted) == false
      max_iterations 2
    end

    step "accepted", current <- result("repair", :state) do
      {:ok, current}
    end

    step "handoff",
      action: AskWorker,
      params: %{
        mission_id: input(:mission_id),
        goal: input(:goal),
        role: "delivery",
        revision: result("accepted", :revision),
        inputs: %{package: result("accepted", :package), review: result("accepted", :review)}
      }

    output %{
      mission: result("accepted"),
      repairs: result("repair", :iterations),
      handoff: result("handoff")
    }
  end
end

defmodule Jido.Examples.Applications.Coordinator.PlanDelegate do
  use Jido.Action, name: "pressure_coordinator_plan_delegate"

  @impl Jido.Action
  def run(%{task: task, test: test}, _context) do
    {:ok, %{task: task, test: test}}
  end
end

defmodule Jido.Examples.Applications.Coordinator.ContinueDelegate do
  use Jido.Action, name: "pressure_coordinator_continue_delegate"

  @impl Jido.Action
  def run(input, _context) do
    {:continue, input, Jido.Examples.Applications.Coordinator.Delegate}
  end
end

defmodule Jido.Examples.Applications.Coordinator.DelegateFlow do
  use Jido.Flow, name: "pressure_coordinator_delegate_flow"

  flow do
    dispatch "delegate",
      decision: Jido.Examples.Applications.Coordinator.PlanDelegate,
      expander: Jido.Examples.Applications.Coordinator.ContinueDelegate,
      params: %{task: input(:task), test: input(:test)}

    output result("delegate")
  end
end

defmodule Jido.Examples.Applications.Coordinator.Delegate do
  use Jido.Action, name: "pressure_coordinator_delegate"

  alias Jido.Agent.Directive
  alias Jido.Plugin.Scheduler
  alias Jido.Signal
  alias Jido.Examples.Applications.Coordinator.WorkerAgent

  @impl Jido.Action
  def run(%{task: task, test: test}, context) do
    work =
      Signal.new!(
        "worker.task",
        %{task: task, test: test},
        source: "/coordinator/delegate"
      )

    timeout =
      Signal.new!(
        "coordinator.timeout",
        %{task: task},
        source: "/coordinator/delegate"
      )

    next_state = %{
      context.agent_state
      | delegations: context.agent_state.delegations + 1,
        history: context.agent_state.history ++ [%{kind: :delegation, task: task}]
    }

    {:ok, next_state,
     [
       Directive.spawn_agent(WorkerAgent, :worker, restart: :temporary),
       Directive.emit_to_child(:worker, work),
       Scheduler.schedule(100, timeout)
     ]}
  end
end

defmodule Jido.Examples.Applications.Coordinator.Work do
  use Jido.Action, name: "pressure_coordinator_work"

  alias Jido.Agent.Directive
  alias Jido.Signal

  @impl Jido.Action
  def run(%{task: task, test: test}, context) do
    send(test, {:worker_handled, task})

    reply =
      Signal.new!(
        "worker.reply",
        %{task: task},
        source: "/worker"
      )

    next_state = %{
      context.agent_state
      | jobs: context.agent_state.jobs ++ [task]
    }

    {:ok, next_state, [Directive.emit_to_parent(reply)]}
  end
end

defmodule Jido.Examples.Applications.Coordinator.WorkerAgent do
  use Jido.Agent, name: "pressure_coordinator_worker"

  agent do
    schema Zoi.object(%{jobs: Zoi.list(Zoi.any()) |> Zoi.default([])})
  end

  routes do
    route "worker.task", Jido.Examples.Applications.Coordinator.Work
  end
end

defmodule Jido.Examples.Applications.Coordinator.RecordReply do
  use Jido.Action, name: "pressure_coordinator_record_reply"

  @impl Jido.Action
  def run(_input, context) do
    {:ok, %{context.agent_state | replies: context.agent_state.replies + 1}}
  end
end

defmodule Jido.Examples.Applications.Coordinator.RecordTimeout do
  use Jido.Action, name: "pressure_coordinator_record_timeout"

  @impl Jido.Action
  def run(_input, context) do
    {:ok, %{context.agent_state | timeouts: context.agent_state.timeouts + 1}}
  end
end

defmodule Jido.Examples.Applications.Coordinator.RecordChildStarted do
  use Jido.Action, name: "pressure_coordinator_record_child_started"

  @impl Jido.Action
  def run(_input, context) do
    {:ok, %{context.agent_state | child_starts: context.agent_state.child_starts + 1}}
  end
end

defmodule Jido.Examples.Applications.Coordinator.Agent do
  use Jido.Agent, name: "pressure_coordinator_agent"

  agent do
    schema Zoi.object(%{
             delegations: Zoi.integer() |> Zoi.default(0),
             history: Zoi.list(Zoi.map()) |> Zoi.default([]),
             replies: Zoi.integer() |> Zoi.default(0),
             timeouts: Zoi.integer() |> Zoi.default(0),
             child_starts: Zoi.integer() |> Zoi.default(0)
           })

    plugin Jido.Plugin.Scheduler
  end

  routes do
    route "coordinator.delegate", Jido.Examples.Applications.Coordinator.DelegateFlow
    route "worker.reply", Jido.Examples.Applications.Coordinator.RecordReply
    route "coordinator.timeout", Jido.Examples.Applications.Coordinator.RecordTimeout
    route "jido.agent.child.started", Jido.Examples.Applications.Coordinator.RecordChildStarted
  end
end

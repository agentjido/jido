defmodule JidoTest.AgentFixtures do
  @moduledoc false

  alias Jido.Flow
  alias Jido.Flow.Ref
  alias __MODULE__.{Add, DispatchDecision, DispatchExpander}

  def two_step_flow do
    Flow.new!(%{
      name: "agent_server_two_step_flow",
      components: [
        %{
          kind: :step,
          name: "first",
          action: Add,
          params: %{
            by: Ref.input(:first_by),
            label: Ref.input(:first_label)
          }
        },
        %{
          kind: :step,
          name: "second",
          action: Add,
          params: %{
            state: Ref.result("first"),
            by: Ref.input(:second_by),
            label: Ref.input(:second_label)
          }
        }
      ],
      output: Ref.result("second")
    })
  end

  def dispatch_flow do
    dispatch =
      %{
        kind: :dispatch,
        name: "dispatch",
        decision: DispatchDecision,
        expander: DispatchExpander,
        params: %{
          by: Ref.input(:by),
          label: Ref.input(:label)
        }
      }

    Flow.new!(%{
      name: "agent_server_dispatch_flow",
      components: [dispatch],
      output: Ref.result("dispatch")
    })
  end
end

defmodule JidoTest.AgentFixtures.Add do
  @moduledoc false

  use Jido.Action, name: "agent_server_add", output_schema: Zoi.map()

  @impl Jido.Action
  def run(%{by: by, label: label} = params, context) do
    state = Map.get(params, :state, context.agent_state)

    if test_pid = Map.get(params, :test_pid) do
      send(test_pid, {:agent_action_ran, label, self()})
    end

    {:ok,
     %{
       state
       | count: state.count + by,
         history: state.history ++ [label]
     }}
  end
end

defmodule JidoTest.AgentFixtures.CounterAgent do
  @moduledoc false

  use Jido.Agent, name: "counter_agent", description: "A module-authored Agent"

  state do
    schema Zoi.object(%{
             count: Zoi.integer() |> Zoi.default(0),
             history: Zoi.list(Zoi.string()) |> Zoi.default([])
           })
  end

  routes do
    route "counter.add", JidoTest.AgentFixtures.Add do
      state(from: output())
    end
  end
end

defmodule JidoTest.AgentFixtures.BlockingAdd do
  @moduledoc false

  use Jido.Action,
    name: "agent_server_blocking_add",
    output_schema: Zoi.any()

  alias JidoTest.AgentFixtures.Add

  @impl Jido.Action
  def run(%{test_pid: test_pid, gate: gate} = params, context) do
    send(test_pid, {:agent_action_blocked, gate, self()})

    receive do
      {:release, ^gate} -> Add.run(params, context)
    end
  end
end

defmodule JidoTest.AgentFixtures.ContinueToAdd do
  @moduledoc false

  use Jido.Action,
    name: "agent_server_continue_to_add",
    output_schema: Zoi.any()

  alias JidoTest.AgentFixtures.Add

  @impl Jido.Action
  def run(params, _context), do: {:continue, params, Add}
end

defmodule JidoTest.AgentFixtures.ReentrantCall do
  @moduledoc false

  use Jido.Action,
    name: "agent_server_reentrant_call",
    output_schema: Zoi.any()

  @impl Jido.Action
  def run(%{server: server, test_pid: test_pid}, context) do
    signal = Jido.Signal.new!("counter.reentrant", %{}, source: "/agent-reentrant-action")
    result = Jido.AgentServer.call(server, signal, 1_000)
    send(test_pid, {:agent_reentrant_result, result})
    {:ok, context.agent_state}
  end
end

defmodule JidoTest.AgentFixtures.ObserveExecutionBoundary do
  @moduledoc false

  use Jido.Action,
    name: "agent_server_observe_execution_boundary",
    output_schema: Zoi.any()

  @impl Jido.Action
  def run(%{test_pid: test_pid} = params, context) do
    send(test_pid, {:agent_execution_boundary, params, context})
    {:ok, context.agent_state}
  end
end

defmodule JidoTest.AgentFixtures.DispatchDecision do
  @moduledoc false

  use Jido.Action,
    name: "agent_server_dispatch_decision",
    output_schema: Zoi.any()

  @impl Jido.Action
  def run(params, _context), do: {:ok, params}
end

defmodule JidoTest.AgentFixtures.DispatchExpander do
  @moduledoc false

  use Jido.Action,
    name: "agent_server_dispatch_expander",
    output_schema: Zoi.any()

  alias JidoTest.AgentFixtures.Add

  @impl Jido.Action
  def run(params, _context), do: {:continue, params, Add}
end

defmodule JidoTest.AgentFixtures.Fail do
  @moduledoc false

  use Jido.Action,
    name: "agent_server_fail",
    output_schema: Zoi.any()

  @impl Jido.Action
  def run(_params, _context), do: {:error, :expected_failure}
end

defmodule JidoTest.AgentFixtures.InvalidState do
  @moduledoc false

  use Jido.Action,
    name: "agent_server_invalid_state",
    output_schema: Zoi.any()

  @impl Jido.Action
  def run(_params, _context), do: {:ok, %{count: :invalid, history: []}}
end

defmodule JidoTest.AgentFixtures.TestDirective do
  @moduledoc false

  @enforce_keys [:name, :test_pid]
  defstruct @enforce_keys
end

defmodule JidoTest.AgentFixtures.WithDirective do
  @moduledoc false

  use Jido.Action,
    name: "agent_server_with_directive",
    output_schema: Zoi.any()

  alias JidoTest.AgentFixtures.{Add, TestDirective}

  @impl Jido.Action
  def run(%{directive_name: name, test_pid: test_pid} = params, context) do
    {:ok, state} = Add.run(params, context)
    {:ok, state, [%TestDirective{name: name, test_pid: test_pid}]}
  end
end

defmodule JidoTest.AgentFixtures.InvalidBehavior do
  @moduledoc false
end

defmodule Jido.Test.AgentServer.Fixtures do
  @moduledoc false

  alias Jido.Flow
  alias Jido.Flow.Ref
  alias __MODULE__.{Add, InvokeDecision, InvokeExpander}

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

  def invoke_flow do
    invoke =
      %{
        kind: :invoke,
        name: "invoke",
        decision: InvokeDecision,
        expander: InvokeExpander,
        params: %{
          by: Ref.input(:by),
          label: Ref.input(:label)
        }
      }

    Flow.new!(%{
      name: "agent_server_invoke_flow",
      components: [invoke],
      output: Ref.result("invoke")
    })
  end
end

defmodule Jido.Test.AgentServer.Fixtures.Add do
  @moduledoc false

  use Jido.Action, name: "agent_server_add"

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

defmodule Jido.Test.AgentServer.Fixtures.CounterAgent do
  @moduledoc false

  use Jido.Agent, name: "counter_agent", description: "A module-authored Agent"

  state do
    schema Jido.Joi.object(%{
             count: Jido.Joi.integer() |> Jido.Joi.default(0),
             history: Jido.Joi.list(Jido.Joi.string()) |> Jido.Joi.default([])
           })
  end

  routes do
    route "counter.add", Jido.Test.AgentServer.Fixtures.Add
  end
end

defmodule Jido.Test.AgentServer.Fixtures.BlockingAdd do
  @moduledoc false

  use Jido.Action,
    name: "agent_server_blocking_add"

  alias Jido.Test.AgentServer.Fixtures.Add

  @impl Jido.Action
  def run(%{test_pid: test_pid, gate: gate} = params, context) do
    send(test_pid, {:agent_action_blocked, gate, self()})

    receive do
      {:release, ^gate} -> Add.run(params, context)
    end
  end
end

defmodule Jido.Test.AgentServer.Fixtures.ContinueToAdd do
  @moduledoc false

  use Jido.Action,
    name: "agent_server_continue_to_add"

  alias Jido.Test.AgentServer.Fixtures.Add

  @impl Jido.Action
  def run(params, _context), do: {:continue, params, Add}
end

defmodule Jido.Test.AgentServer.Fixtures.ReentrantCall do
  @moduledoc false

  use Jido.Action,
    name: "agent_server_reentrant_call"

  @impl Jido.Action
  def run(%{server: server, test_pid: test_pid}, context) do
    signal = Jido.Signal.new!("counter.reentrant", %{}, source: "/agent-reentrant-action")
    result = Jido.AgentServer.call(server, signal, 1_000)
    send(test_pid, {:agent_reentrant_result, result})
    {:ok, context.agent_state}
  end
end

defmodule Jido.Test.AgentServer.Fixtures.ObserveExecutionBoundary do
  @moduledoc false

  use Jido.Action,
    name: "agent_server_observe_execution_boundary"

  @impl Jido.Action
  def run(%{test_pid: test_pid} = params, context) do
    send(test_pid, {:agent_execution_boundary, params, context})
    {:ok, context.agent_state}
  end
end

defmodule Jido.Test.AgentServer.Fixtures.InvokeDecision do
  @moduledoc false

  use Jido.Action,
    name: "agent_server_invoke_decision"

  @impl Jido.Action
  def run(params, _context), do: {:ok, params}
end

defmodule Jido.Test.AgentServer.Fixtures.InvokeExpander do
  @moduledoc false

  use Jido.Action,
    name: "agent_server_invoke_expander"

  alias Jido.Test.AgentServer.Fixtures.Add

  @impl Jido.Action
  def run(params, _context), do: {:continue, params, Add}
end

defmodule Jido.Test.AgentServer.Fixtures.Fail do
  @moduledoc false

  use Jido.Action,
    name: "agent_server_fail"

  @impl Jido.Action
  def run(_params, _context), do: {:error, :expected_failure}
end

defmodule Jido.Test.AgentServer.Fixtures.InvalidState do
  @moduledoc false

  use Jido.Action,
    name: "agent_server_invalid_state"

  @impl Jido.Action
  def run(_params, _context), do: {:ok, %{count: :invalid, history: []}}
end

defmodule Jido.Test.AgentServer.Fixtures.TestDirective do
  @moduledoc false

  @enforce_keys [:name, :test_pid]
  defstruct @enforce_keys
end

defmodule Jido.Test.AgentServer.Fixtures.WithDirective do
  @moduledoc false

  use Jido.Action,
    name: "agent_server_with_directive"

  alias Jido.Test.AgentServer.Fixtures.{Add, TestDirective}

  @impl Jido.Action
  def run(%{directive_name: name, test_pid: test_pid} = params, context) do
    {:ok, state} = Add.run(params, context)
    {:ok, state, [%TestDirective{name: name, test_pid: test_pid}]}
  end
end

defmodule Jido.Test.AgentServer.Fixtures.InvalidBehavior do
  @moduledoc false
end

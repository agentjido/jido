defmodule Jido.Examples.ActionExecTest do
  use ExUnit.Case

  require Logger
  alias Jido.Tools.Basic.Log, as: LogAction
  alias JidoTest.TestAgents.BasicAgent, as: B
  alias Jido.Instruction

  @moduletag :capture_log

  defmodule MyWorkflow do
    use Jido.Tools.Workflow,
      name: "my_workflow",
      description: "My workflow",
      schema: [
        input: [
          type: :non_neg_integer,
          doc: "The number of steps to execute",
          default: 10
        ]
      ],
      workflow: [
        {:step, [name: "step_1"],
         [%Instruction{action: LogAction, params: %{level: :debug, message: "Step 1"}}]},
        {:step, [name: "step_2"],
         [%Instruction{action: LogAction, params: %{level: :info, message: "Step 2"}}]},
        {:step, [name: "step_3"],
         [%Instruction{action: LogAction, params: %{level: :warning, message: "Step 3"}}]}
      ]
  end

  test "example action" do
    {:ok, pid} =
      B.start_link(
        log_level: :debug,
        dispatch: [],
        actions: [MyWorkflow]
      )

    # {:ok, agent_state} = B.state(pid)
    # Logger.info("Agent state: #{inspect(agent_state, pretty: true)}")

    result = B.call(pid, %Instruction{action: MyWorkflow, params: %{input: 3}})

    assert result == {:ok, %{input: 3, message: "Step 3", level: :warning}}
    # IO.inspect(result, pretty: true)
  end
end

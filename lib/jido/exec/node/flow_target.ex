defmodule Jido.Exec.Node.FlowTarget do
  @moduledoc false

  alias Jido.Error
  alias Jido.Exec.{Compiler, Result, Runtime}
  alias Jido.Instruction
  alias Runic.Workflow

  @doc false
  @spec run(Instruction.t(), map(), struct(), Workflow.t() | nil) ::
          {:ok, term(), [term()]} | {:error, Exception.t()}
  def run(%Instruction{} = instruction, runtime, node, workflow \\ nil) do
    with {:ok, workflow} <- workflow(instruction, workflow),
         :ok <- reject_wait(workflow, node) do
      execute(workflow, instruction, runtime, node)
    end
  end

  defp workflow(_instruction, %Workflow{} = workflow), do: {:ok, workflow}
  defp workflow(instruction, nil), do: Compiler.compile(%{instruction | context: %{}}, [])

  defp execute(workflow, instruction, runtime, node) do
    run_context =
      instruction.context
      |> Runtime.caller_context()
      |> Map.merge(runtime)

    {workflow, observation} =
      Runtime.with_quiet_failure_logging(fn ->
        workflow
        |> Workflow.enable_event_emission()
        |> Workflow.put_run_context(%{_global: run_context})
        |> Workflow.execute(Jido.Exec.Fact.local_value(instruction.params),
          runnable_order: &Result.runnable_order/1
        )
      end)

    case Result.project(workflow, observation) do
      {:ok, value} -> {:ok, value, []}
      {:ok, value, effects} -> {:ok, value, effects}
      {:handoff, _instruction, _effects} -> nested_handoff(node)
      {:error, error} -> {:error, error}
    end
  end

  defp reject_wait(workflow, node) do
    if Enum.any?(Multigraph.vertices(workflow.graph), &is_struct(&1, Jido.Exec.Node.Wait)) do
      {:error,
       Error.config_error("a nested Flow cannot suspend inside an authored component", %{
         node: node.name,
         reason: :nested_wait
       })}
    else
      :ok
    end
  end

  defp nested_handoff(node) do
    {:error,
     Error.config_error("handoff must finish the root Flow", %{
       node: node.name,
       reason: :nested_handoff
     })}
  end
end

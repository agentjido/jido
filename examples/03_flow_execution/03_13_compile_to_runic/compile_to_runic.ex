defmodule Jido.Examples.Execution.CompileToRunic.Add do
  use Jido.Action, name: "example_exec_compile_add"

  @impl true
  def run(%{value: value, amount: amount}, _context), do: {:ok, %{value: value + amount}}
end

defmodule Jido.Examples.Execution.CompileToRunic.Multiply do
  use Jido.Action, name: "example_exec_compile_multiply"

  @impl true
  def run(%{value: value, amount: amount}, _context), do: {:ok, %{value: value * amount}}
end

defmodule Jido.Examples.Execution.CompileToRunic do
  alias Jido.Examples.Execution.CompileToRunic.{Add, Multiply}
  alias Jido.Flow
  alias Jido.Flow.Ref
  alias Runic.Workflow

  def flow do
    Flow.new!(%{
      name: "example_exec_compile_to_runic",
      components: [
        %{
          kind: :step,
          name: "add",
          action: Add,
          params: %{value: Ref.input(:value), amount: 2}
        },
        %{
          kind: :step,
          name: "multiply",
          action: Multiply,
          params: %{value: Ref.result("add", :value), amount: 3}
        }
      ],
      output: Ref.result("multiply")
    })
  end

  def compile, do: Jido.Exec.compile(flow(), [])

  def component_summary(workflow) do
    workflow
    |> Workflow.components()
    |> Map.values()
    |> Enum.map(&{&1.name, &1.__struct__})
    |> Enum.sort()
  end

  def connection_summary(workflow) do
    workflow
    |> Workflow.component_graph()
    |> Multigraph.edges()
    |> Enum.map(fn edge -> {edge.v1.name, edge.v2.name} end)
    |> Enum.sort()
  end

  def execute(workflow, params) do
    {workflow, observation} = Workflow.execute(workflow, params)
    Jido.Exec.result(workflow, observation)
  end

  def main do
    {:ok, workflow} = compile()

    IO.inspect(flow(), label: "Jido Flow")
    IO.inspect(component_summary(workflow), label: "Runic components")
    IO.inspect(connection_summary(workflow), label: "Runic connections")
    IO.inspect(execute(workflow, %{value: 4}), label: "Jido result")
  end
end

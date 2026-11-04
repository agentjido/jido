defmodule Jido.Examples.Compilation.DependencyGraph.Work do
  use Jido.Action, name: "example_compile_dependency_graph_work"

  @impl true
  def run(params, _context), do: {:ok, params}
end

defmodule Jido.Examples.Compilation.DependencyGraph do
  alias Jido.Examples.Compilation.DependencyGraph.Work
  alias Jido.Flow.Ref

  def definition do
    %{
      name: "example_compile_dependency_graph",
      components: [
        %{
          kind: :step,
          name: "load",
          action: Work,
          params: %{operation: :load, order_id: Ref.input(:order_id)}
        },
        %{
          kind: :step,
          name: "audit",
          action: Work,
          params: %{operation: :audit, order_id: Ref.input(:order_id)}
        },
        %{
          kind: :step,
          name: "charge",
          action: Work,
          params: %{operation: :charge, order: Ref.result("load")}
        },
        %{
          kind: :step,
          name: "save",
          action: Work,
          params: %{operation: :save, charge: Ref.result("charge")},
          needs: ["audit"]
        }
      ],
      output: %{receipt: Ref.result("save"), audit: Ref.result("audit")}
    }
  end

  def flow, do: Jido.Flow.new!(definition())
end

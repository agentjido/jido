defmodule Jido.Test.Perf.Flow.Identity do
  use Jido.Action, name: "action_flow_benchmark_identity"

  @impl true
  def run(params, _context), do: {:ok, %{value: params.value}}
end

defmodule Jido.Test.Perf.Flow.StaticFlow do
  use Jido.Flow, name: "action_flow_benchmark_static"

  alias Jido.Test.Perf.Flow.Identity

  flow do
    step "first", action: Identity, params: %{value: input(:value)}
    step "second", action: Identity, params: %{value: result("first", :value)}
    output result("second")
  end
end

defmodule Jido.Test.Perf.Flow.Fixtures do
  @moduledoc false

  alias Jido.Test.Perf.Flow.Identity
  alias Jido.Flow.Ref

  def wide_input(width) when is_integer(width) and width > 0 do
    ids = Enum.map(1..width, &"branch_#{&1}")

    %{
      name: "action_flow_benchmark_wide_#{width}",
      components:
        Enum.map(ids, fn id ->
          %{
            kind: :step,
            name: id,
            action: Identity,
            params: %{value: Ref.input(:value)}
          }
        end),
      output: Ref.result(List.last(ids))
    }
  end

  def wide_flow(width), do: width |> wide_input() |> Jido.Flow.new!()
end

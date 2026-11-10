defmodule Jido.Flow.ActionBoundaryTest do
  use ExUnit.Case, async: true

  alias Jido.Flow
  alias Jido.Flow.Ref

  defmodule Increment do
    use Jido.Action,
      name: "flow_action_boundary_increment",
      schema: Jido.Joi.object(%{value: Jido.Joi.integer()}),
      output_schema: Jido.Joi.object(%{value: Jido.Joi.integer()})

    @impl true
    def run(%{value: value}, _context), do: {:ok, %{value: value + 1}, [:incremented]}
  end

  defmodule ExistingFlow do
    use Jido.Flow, name: "flow_action_boundary_existing"

    flow do
      step "increment", action: Increment, params: input()
      output result("increment")
    end
  end

  test "an Action becomes one canonical Flow step" do
    assert {:ok,
            %Flow{
              components: %{
                "action" => %{
                  kind: :call,
                  call: %{kind: :action, target: Increment, params: %Ref{source: :input, path: []}}
                }
              },
              output: %Ref{source: :result, component: "action", path: []}
            } = flow} = Flow.from_action(Increment)

    assert {:ok, %{value: 2}, [:incremented]} = Jido.Exec.run(flow, %{value: 1})
    assert {:error, %Jido.Error.ValidationError{}} = Jido.Exec.run(flow, %{value: "one"})
  end

  test "the conversion rejects a Flow and non-module values" do
    assert {:error, %Jido.Error.ValidationError{}} = Flow.from_action(ExistingFlow)
    assert {:error, %Jido.Error.ValidationError{}} = Flow.from_action(:not_a_module)
    assert {:error, %Jido.Error.ValidationError{}} = Flow.from_action(%{})
  end
end

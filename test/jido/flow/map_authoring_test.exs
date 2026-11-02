defmodule Jido.Flow.MapAuthoringTest do
  use ExUnit.Case, async: true

  alias Jido.Flow.Ref
  alias JidoActionTest.Fixtures.Actions.Add

  test "component maps normalize atom and string names to the same canonical Flow" do
    attrs = %{name: "map_authoring", output: Ref.result("add")}

    component = %{
      kind: :step,
      name: "add",
      action: Add,
      params: %{value: Ref.input(:value), amount: 1}
    }

    assert {:ok, flow} = JidoActionTest.FlowBuilder.new(Map.put(attrs, :components, [component]))

    assert Jido.Flow.new(Map.put(attrs, :components, [%{component | name: :add}])) ==
             {:ok, flow}

    assert Jido.Exec.run(flow, %{value: 4}) == {:ok, %{value: 5}}
  end

  test "unknown or missing component kinds return structured errors" do
    for component <- [
          %{kind: :unknown, name: "node"},
          %{name: "node"},
          %{kind: "step", name: "node"}
        ] do
      assert {:error, %Jido.Flow.Error.InvalidDefinitionError{}} =
               JidoActionTest.FlowBuilder.new(%{
                 name: "bad_map",
                 components: [component],
                 output: %{}
               })
    end
  end
end

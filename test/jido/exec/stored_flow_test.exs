defmodule Jido.Exec.StoredFlowTest do
  use ExUnit.Case, async: true

  alias Jido.Exec
  alias Jido.Flow
  alias Jido.Flow.{Codec, Ref}
  alias JidoActionTest.FlowCodec, as: Codec
  alias JidoActionTest.Fixtures.Actions.Add

  test "a JSON Flow keeps stable executable component identities" do
    flow = ten_step_flow()

    assert {:ok, document, registry} = Codec.encode(flow)

    assert {:ok, restored} =
             document
             |> Jason.encode!()
             |> Jason.decode!()
             |> Codec.decode(registry)

    assert restored == flow
    assert {:ok, original_workflow} = Exec.compile(flow)
    assert {:ok, restored_workflow} = Exec.compile(restored)

    for step <- 1..10 do
      name = "step_#{step}"
      original = Runic.Workflow.get_component(original_workflow, name)
      hydrated = Runic.Workflow.get_component(restored_workflow, name)

      assert %Jido.Exec.Node.Action{} = original
      assert hydrated.hash == original.hash
      assert hydrated.id == original.id
    end

    assert Exec.run(restored, %{value: 0}) == {:ok, %{value: 10}}
  end

  defp ten_step_flow do
    components =
      Enum.map(1..10, fn step ->
        value = if step == 1, do: Ref.input(:value), else: Ref.result("step_#{step - 1}", :value)

        %{
          kind: :step,
          name: "step_#{step}",
          action: Add,
          params: %{value: value, amount: 1}
        }
      end)

    Flow.new!(%{
      name: "stored_ten_steps",
      components: components,
      output: Ref.result("step_10")
    })
  end
end

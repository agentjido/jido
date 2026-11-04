Code.require_file("../support/flows/components.ex", __DIR__)
Code.require_file("../support/flows/hostile.ex", __DIR__)

defmodule JidoActionTest.Authoring.SchemaPipelineTest do
  use ExUnit.Case, async: false
  @moduletag :authoring

  alias Jido.Exec
  alias JidoActionTest.Authoring.Hostile.SchemaPipeline

  test "one composed Flow validates defaults and every input or output boundary" do
    context = %{label: "child", observer: self()}

    assert Exec.run(SchemaPipeline, %{}, context) == {:ok, %{value: 3}}
    assert_receive :schema_first_called
    assert_receive {:hostile_action, %{phase: "after", value: 3}}

    assert {:error, root_input_error} = Exec.run(SchemaPipeline, %{flag: :bad}, context)
    assert root_input_error.details.phase == :flow_input
    assert hd(root_input_error.details.errors).path == [:flag]
    refute_received :schema_first_called
    refute_received {:hostile_action, _}

    assert {:error, action_input_error} = Exec.run(SchemaPipeline, %{value: "bad"}, context)
    assert action_input_error.details.node_path == ["first"]
    refute_received :schema_first_called
    refute_received {:hostile_action, _}

    assert {:error, action_output_error} =
             Exec.run(SchemaPipeline, %{}, Map.put(context, :bad_action_output, true))

    assert action_output_error.details.node_path == ["first"]
    assert_receive :schema_first_called
    refute_received {:hostile_action, _}

    assert {:error, child_input_error} = Exec.run(SchemaPipeline, %{child: "bad"}, context)
    assert child_input_error.details.node_path == ["child"]
    assert_receive :schema_first_called
    refute_received {:hostile_action, _}

    assert {:error, root_output_error} =
             Exec.run(SchemaPipeline, %{root_output: "bad"}, context)

    assert root_output_error.details.phase == :flow_output
    assert hd(root_output_error.details.errors).path == [:value]
    assert_receive :schema_first_called
    assert_receive {:hostile_action, %{phase: "after", value: "bad"}}
    refute_received {:hostile_action, _}
  end
end

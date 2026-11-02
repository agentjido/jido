defmodule Jido.Flow.BoundaryTest do
  use ExUnit.Case, async: true

  alias Jido.Action.Output
  alias Jido.Flow
  alias Jido.Flow.Error.InvalidDefinitionError
  alias Jido.Flow.Ref
  alias JidoActionTest.Fixtures.Actions.BasicAction

  defmodule SchemaOwner do
    def schema, do: Zoi.object(%{value: Zoi.integer()})
    def output_schema, do: Zoi.object(%{result: Zoi.integer()})
  end

  test "rejects invalid public boundary subjects" do
    for operation <- [
          &Flow.new/1,
          &Flow.validate/1,
          &Flow.dependencies/1,
          &Flow.explain/1,
          &Flow.semantic_identity/1
        ] do
      assert {:error, %InvalidDefinitionError{}} = operation.(42)
    end

    assert_raise InvalidDefinitionError, fn -> Flow.new!(%{}) end
  end

  test "detects a noncanonical Flow value" do
    flow = valid_flow()
    changed = %{flow | identity: %{algorithm: :sha256, digest: "changed", uuid: "changed"}}

    assert {:error, %InvalidDefinitionError{details: %{reason: :non_canonical}}} =
             Flow.validate(changed)
  end

  test "owns Flow input and output validation" do
    assert {:ok, %{value: 1}} = Flow.validate_params_for(%{value: 1}, SchemaOwner)

    assert {:error, %InvalidDefinitionError{}} =
             Flow.validate_params_for(%{value: "bad"}, SchemaOwner)

    assert {:ok, %{result: 2}} = Flow.validate_output_for(%{result: 2}, SchemaOwner)

    assert {:error, %InvalidDefinitionError{}} =
             Flow.validate_output_for(%{result: "bad"}, SchemaOwner)

    assert {:ok, %Output{kind: :raw}} =
             Flow.validate_output_for(Output.raw("done"), SchemaOwner)

    invalid = %Output{kind: :batch, value: :not_a_list, meta: %{}}

    assert {:error, %InvalidDefinitionError{}} =
             Flow.validate_output_for(invalid, SchemaOwner)
  end

  defp valid_flow do
    Flow.new!(%{
      name: "boundary_flow",
      forms: %{"work" => BasicAction},
      output: Ref.result("work")
    })
  end
end

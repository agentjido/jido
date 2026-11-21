defmodule Jido.AI.Tools.ToolSchemaDefaultsTest do
  use ExUnit.Case, async: true

  alias Jido.AI.Toolset

  defmodule Lookup do
    use Jido.Action,
      name: "tool_schema_defaults_lookup",
      schema:
        Jido.Joi.object(%{
          order_id: Jido.Joi.string(),
          note: Jido.Joi.string() |> Jido.Joi.default("none"),
          filter:
            Jido.Joi.object(%{
              status: Jido.Joi.string(),
              limit: Jido.Joi.integer() |> Jido.Joi.default(10)
            })
        })

    @impl true
    def run(params, _context), do: {:ok, params}
  end

  test "a tool definition does not require a defaulted field" do
    assert {:ok, [tool]} = Toolset.definitions([Lookup])
    json = ReqLLM.Schema.to_json(tool.parameter_schema)

    assert Enum.sort(json["required"]) == ["filter", "order_id"]
    assert json["properties"]["note"]["default"] == "none"
    assert json["properties"]["filter"]["required"] == ["status"]
    assert tool.strict
  end
end

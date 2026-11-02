defmodule Jido.Flow.DiagnosticPathsTest do
  use ExUnit.Case, async: true

  alias Jido.Flow
  alias Jido.Authoring.Registry
  alias Jido.Flow.Codec
  alias JidoActionTest.FlowCodec, as: Codec
  alias JidoActionTest.Fixtures.Actions.EchoParamsAction

  @empty %{"$type" => "map", "entries" => []}

  test "Flow.validate reports canonical component errors by component name" do
    {:ok, flow} =
      Flow.new(%{
        name: "paths",
        components: [
          %{kind: :step, name: "zeta", action: EchoParamsAction},
          %{kind: :step, name: "alpha", action: EchoParamsAction},
          %{kind: :step, name: "mid", action: EchoParamsAction}
        ],
        output: %{}
      })

    for name <- ["alpha", "mid", "zeta"] do
      instruction = flow.components[name].call
      invalid = put_in(flow.components[name].call, Map.put(instruction, :params, %{v: {:tuple}}))

      assert {:error, error} = Flow.validate(invalid)
      assert error.details.path == [:components, name, :call, :params, :v]
    end
  end

  test "Flow.new reports graph error locations as paths" do
    assert {:error, error} =
             Flow.new(%{
               name: "paths",
               components: [
                 %{kind: :step, name: "a", action: EchoParamsAction},
                 %{kind: :step, name: "a", action: EchoParamsAction}
               ],
               output: %{}
             })

    assert error.details.path == [:components, 1, :name]

    assert {:error, error} =
             Flow.new(%{
               name: "paths",
               components: [%{kind: :step, name: "", action: EchoParamsAction}],
               output: %{}
             })

    assert error.details.path == [:components, 0, :name]
  end

  test "Codec diagnostics keep a missing output and field paths for component rules" do
    assert {:error, errors} =
             Codec.diagnose(document([step("a", %{"needs" => ["missing"]})], nil), registry())

    assert ["Flow output is required", "Flow reference points to an unknown component"] =
             messages(errors)

    assert {:error, errors} =
             Codec.diagnose(
               document([step("a", %{}), step("b", %{"needs" => ["a", "a"]})], result_ref("b")),
               registry()
             )

    assert [["components", 1, "needs"]] = paths(errors)

    iterate = %{
      "kind" => "iterate",
      "name" => "loop",
      "state" => %{
        "schema" => %{"id" => "schemas/map", "vsn" => 1},
        "initial" => @empty,
        "update" => %{"$ref" => %{"source" => "body_result", "component" => nil, "path" => []}}
      },
      "completion" => false,
      "max_iterations" => 20_000,
      "needs" => [],
      "meta" => @empty,
      "call" => %{
        "kind" => "action",
        "target" => %{"id" => "actions/echo", "vsn" => 1},
        "params" => @empty
      }
    }

    assert {:error, errors} = Codec.diagnose(document([iterate], result_ref("loop")), registry())
    assert [["components", 0, "max_iterations"]] = paths(errors)

    option = fn condition ->
      %{
        "name" => "o",
        "condition" => condition,
        "call" => %{
          "kind" => "action",
          "target" => %{"id" => "actions/echo", "vsn" => 1},
          "params" => @empty
        }
      }
    end

    choice = %{
      "kind" => "choice",
      "name" => "c",
      "options" => [option.(true), option.(false)],
      "fallback" => %{
        "kind" => "action",
        "target" => %{"id" => "actions/echo", "vsn" => 1},
        "params" => @empty
      },
      "needs" => [],
      "meta" => @empty
    }

    assert {:error, errors} = Codec.diagnose(document([choice], result_ref("c")), registry())
    assert [["components", 0, "options"]] = paths(errors)
  end

  test "Codec diagnostics identify a missing reference vsn" do
    invalid =
      document([step("a", %{})], result_ref("a"))
      |> put_in(
        ["components", Access.at(0), "call", "target"],
        %{"id" => "actions/echo"}
      )

    assert {:error, errors} = Codec.diagnose(invalid, registry())
    assert [["components", 0, "call", "target", "vsn"]] = paths(errors)
  end

  defp registry do
    Registry.new!(%{
      {"actions/echo", 1} => {:action, EchoParamsAction},
      {"schemas/map", 1} => {:schema, Zoi.map()}
    })
  end

  defp step(name, extra) do
    Map.merge(
      %{
        "name" => name,
        "needs" => [],
        "meta" => @empty,
        "kind" => "call",
        "call" => %{
          "kind" => "action",
          "target" => %{"id" => "actions/echo", "vsn" => 1},
          "params" => @empty
        }
      },
      extra
    )
  end

  defp document(components, output) do
    %{
      "type" => "jido.flow",
      "vsn" => 2,
      "name" => "paths",
      "description" => nil,
      "schema" => %{"id" => "schemas/map", "vsn" => 1},
      "output_schema" => %{"id" => "schemas/map", "vsn" => 1},
      "components" => components,
      "output" => output
    }
  end

  defp result_ref(component),
    do: %{"$ref" => %{"source" => "result", "component" => component, "path" => []}}

  defp messages(%Jido.Flow.Error.Invalid{errors: errors}), do: Enum.map(errors, & &1.message)
  defp paths(%Jido.Flow.Error.Invalid{errors: errors}), do: Enum.map(errors, & &1.details[:path])
end

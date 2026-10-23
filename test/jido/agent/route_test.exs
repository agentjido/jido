defmodule JidoTest.Agent.RouteTest do
  use ExUnit.Case, async: true

  alias Jido.Agent
  alias Jido.Agent.Route

  defmodule OutputStruct do
    defstruct [:id, :details]
  end

  defmodule NestedOutput do
    use Jido.Action,
      name: "route_nested_output",
      output_schema:
        Zoi.object(%{
          state: Zoi.object(%{count: Zoi.integer()}),
          reply: Zoi.object(%{details: Zoi.object(%{id: Zoi.integer()})})
        })

    def run(_params, _context), do: {:ok, %{}}
  end

  defmodule StructOutput do
    use Jido.Action,
      name: "route_struct_output",
      output_schema:
        Zoi.struct(OutputStruct, %{
          id: Zoi.integer(),
          details: Zoi.object(%{"label" => Zoi.string()})
        })

    def run(_params, _context), do: {:ok, %OutputStruct{}}
  end

  defmodule RootOutput do
    use Jido.Action, name: "route_root_output"
    def run(_params, _context), do: {:ok, %{value: 1}}
  end

  defmodule AmbiguousOutput do
    use Jido.Action,
      name: "route_ambiguous_output",
      output_schema: Zoi.object([{:id, Zoi.integer()}, {"id", Zoi.string()}])

    def run(_params, _context), do: {:ok, %{}}
  end

  defmodule DefaultStateAgent do
    use Jido.Agent, name: "route_default_state"

    routes do
      route "work.run", JidoTest.Agent.RouteTest.RootOutput
    end
  end

  def pass(signal), do: signal

  test "structural normalization does not load an executable target" do
    target = Module.concat(__MODULE__, MissingAction)
    refute Code.ensure_loaded?(target)

    route = %{
      path: "work.run",
      handler: %{kind: :action, target: target},
      state: %{source: :output, path: ["state"]},
      reply: %{
        type: "work.done",
        from: %{source: :output, path: ["reply", "id"]}
      }
    }

    assert {:ok,
            %{
              path: "work.run",
              as: nil,
              defaults: %{},
              handler: %{kind: :action, target: ^target},
              state: %{source: :output, path: ["state"]},
              reply: %{
                type: "work.done",
                from: %{source: :output, path: ["reply", "id"]}
              }
            }} = Route.normalize(route, false)

    refute Code.ensure_loaded?(target)
  end

  test "related normalization resolves root, nested Map, and Struct output paths" do
    assert {:ok, %{state: %{source: :output, path: []}, reply: nil}} =
             Route.normalize(%{
               path: "work.root",
               handler: %{kind: :action, target: RootOutput},
               state: %{source: :output, path: []}
             })

    assert {:ok,
            %{
              state: %{source: :output, path: [:state]},
              reply: %{
                type: "work.done",
                from: %{source: :output, path: [:reply, :details, :id]}
              }
            }} =
             Route.normalize(%{
               path: "work.nested",
               handler: %{kind: :action, target: NestedOutput},
               state: %{source: :output, path: ["state"]},
               reply: %{
                 type: "work.done",
                 from: %{source: :output, path: ["reply", "details", "id"]}
               }
             })

    assert {:ok, %{state: %{path: [:details, "label"]}}} =
             Route.normalize(%{
               path: "work.struct",
               handler: %{kind: :action, target: StructOutput},
               state: %{source: :output, path: ["details", "label"]}
             })
  end

  test "an executable route defaults state to the complete output" do
    assert {:ok, %{state: %{source: :output, path: []}}} =
             Route.normalize(%{
               path: "work.run",
               handler: %{kind: :action, target: NestedOutput}
             })

    assert [%{state: %{source: :output, path: []}}] = DefaultStateAgent.definition().routes
  end

  test "selector structure and reply shape are closed and inert" do
    base = %{
      path: "work.run",
      handler: %{kind: :action, target: NestedOutput},
      state: :unchanged
    }

    for state <- [
          %{source: :state, path: []},
          %{source: :output, path: :state},
          %{source: :output, path: [0]},
          %{source: :output, path: [:state], callback: &Function.identity/1}
        ] do
      assert {:error, %Agent.Error{path: [:state | _]}} =
               Route.normalize(%{base | state: state}, false)
    end

    assert {:error, %Agent.Error{code: :unknown_fields, path: [:reply]}} =
             Route.normalize(
               Map.put(base, :reply, %{
                 type: "work.done",
                 from: %{source: :output, path: []},
                 schema: Zoi.any()
               }),
               false
             )

    assert {:error, %Agent.Error{code: :missing_fields, path: [:reply]}} =
             Route.normalize(Map.put(base, :reply, %{type: "work.done"}), false)
  end

  test "related normalization rejects unresolved and ambiguous schema paths" do
    assert {:error, %Agent.Error{code: :unknown_output_field, path: [:state, :path, 1]}} =
             Route.normalize(%{
               path: "work.run",
               handler: %{kind: :action, target: NestedOutput},
               state: %{source: :output, path: ["state", "missing"]}
             })

    assert {:error, %Agent.Error{code: :ambiguous_output_field, path: [:state, :path, 0]}} =
             Route.normalize(%{
               path: "work.run",
               handler: %{kind: :action, target: AmbiguousOutput},
               state: %{source: :output, path: ["id"]}
             })

    fresh_name = "route_missing_#{System.unique_integer([:positive])}"
    assert_raise ArgumentError, fn -> String.to_existing_atom(fresh_name) end

    assert {:error, %Agent.Error{code: :unknown_output_field}} =
             Route.normalize(%{
               path: "work.run",
               handler: %{kind: :action, target: NestedOutput},
               state: %{source: :output, path: [fresh_name]}
             })

    assert_raise ArgumentError, fn -> String.to_existing_atom(fresh_name) end
  end

  test "terminal handlers normalize to unchanged state and reject output mappings" do
    forward = %{
      path: "work.forward",
      handler: %{kind: :forward, target: %{kind: :parent}}
    }

    transform = %{
      path: "work.transform",
      handler: %{kind: :transform, target: {__MODULE__, :pass, 1}}
    }

    assert {:ok, %{state: :unchanged, reply: nil}} = Route.normalize(forward)
    assert {:ok, %{state: :unchanged, reply: nil}} = Route.normalize(transform)

    for route <- [forward, transform] do
      assert {:error, %Agent.Error{code: :terminal_state, path: [:state]}} =
               route
               |> Map.put(:state, %{source: :output, path: []})
               |> Route.normalize()

      assert {:error, %Agent.Error{code: :terminal_reply, path: [:reply]}} =
               route
               |> Map.put(:reply, %{type: "work.done", from: %{source: :output, path: []}})
               |> Route.normalize()
    end
  end

  test "a reply route requires a nonempty Agent signal source" do
    definition = %{
      name: "reply_source_contract",
      routes: [
        %{
          path: "work.run",
          handler: %{kind: :action, target: NestedOutput},
          state: :unchanged,
          reply: %{type: "work.done", from: %{source: :output, path: ["reply"]}}
        }
      ]
    }

    assert {:error, %Agent.Error{code: :reply_source_required, path: [:signal_source]}} =
             Agent.define(definition)

    assert {:ok, %{routes: [%{reply: %{from: %{path: [:reply]}}}]}} =
             Agent.define(Map.put(definition, :signal_source, "/reply-source"))
  end
end

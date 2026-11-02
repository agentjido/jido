defmodule Jido.Flow.DSL.SourceMapTest do
  use ExUnit.Case, async: true

  alias Jido.Flow.DSL.SourceMap

  test "lowering records component and option indices with their names and nested sources" do
    module = Module.concat(__MODULE__, "Valid#{System.unique_integer([:positive])}")

    source = """
    defmodule #{inspect(module)} do
      use Jido.Flow, name: "indexed_sources"
      alias JidoActionTest.Fixtures.Actions.EchoParamsAction, as: Echo
      flow do
        choice "route" do
          option "selected", condition: true, action: Echo, params: %{}
          otherwise action: Echo, params: %{}
        end
        iterate "loop" do
          state Zoi.map(), initial: %{}
          action Echo
          params state()
          repeat 1
        end
        output result("loop")
      end
    end
    """

    Code.compile_string(source, "indexed_sources.ex")
    sources = module.__jido_flow_source_map__()

    for {path, line} <- [
          {[:components, "route"], 5},
          {[:components, 0], 5},
          {[:components, "route", :options, "selected"], 6},
          {[:components, 0, :options, 0], 6},
          {[:components, "route", :fallback], 7},
          {[:components, 0, :fallback], 7},
          {[:components, "loop", :state], 10},
          {[:components, 1, :state], 10},
          {[:components, "loop", :state, :update], 9},
          {[:components, 1, :state, :update], 9},
          {[:output], 15}
        ] do
      assert SourceMap.lookup(sources, %{path: path ++ [:nested]}) ==
               %{file: "indexed_sources.ex", line: line}
    end

    assert module.flow().components["loop"].state.update == Jido.Flow.Ref.body_result()
  end

  test "error paths select the closest declaration before component or role hints" do
    component = %{file: "flow.ex", line: 4}
    option = %{file: "flow.ex", line: 5}
    fallback = %{file: "flow.ex", line: 6}

    sources = %{
      [:components, "route"] => component,
      [:components, "route", :options, "selected"] => option,
      [:components, "route", :fallback] => fallback
    }

    assert SourceMap.lookup(sources, %{
             path: [:components, "route", :options, "selected", :call, :params, :nested],
             component: "route",
             field: :fallback
           }) == option

    assert SourceMap.lookup(sources, %{component: "route", field: "selected"}) == option
    assert SourceMap.lookup(sources, %{component: "route", field: :fallback}) == fallback
    assert SourceMap.lookup(sources, %{component: "route", field: "missing"}) == component
    assert SourceMap.lookup(sources, %{component: "route"}) == component
    assert SourceMap.lookup(sources, %{path: [:output]}) == nil
    assert SourceMap.lookup(sources, %{}) == nil
  end
end

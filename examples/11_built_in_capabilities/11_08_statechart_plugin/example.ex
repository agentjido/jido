defmodule Jido.Examples.Statechart.Release do
  @moduledoc "Uses a chart to control release approval alongside a separate Agent route."

  alias Jido.Joi

  defmodule Chart do
    @moduledoc "Approves a release after the review Signal reports passing checks."

    use Jido.Statechart,
      registry: %{guards: %{"checks_passed" => {__MODULE__, :checks_passed?}}},
      chart: ~SCXML"""
      <scxml xmlns="http://www.w3.org/2005/07/scxml" version="1.0" initial="review">
        <state id="review">
          <transition event="examples.statechart.release.reviewed" cond="checks_passed" target="approved"/>
        </state>
        <final id="approved"/>
      </scxml>
      """

    def checks_passed?(%{event: %{data: %{"checks_passed" => true}}}), do: true
    def checks_passed?(_input), do: false
  end

  use Jido.Agent,
    name: "statechart_release",
    plugins: [{Jido.Plugin.Statechart, %{chart: Chart}}]

  state do
    schema Joi.object(%{notes: Joi.integer() |> Joi.default(0)})
  end

  routes do
    route "examples.statechart.release.reviewed", Jido.Plugin.Statechart.Route, as: :review

    route "examples.statechart.release.note", as: :note do
      flow do
        step "record", _input <- input(), inline: [context: context] do
          state = context.agent_state
          {:ok, %{state | notes: state.notes + 1}}
        end

        output result("record")
      end
    end
  end
end

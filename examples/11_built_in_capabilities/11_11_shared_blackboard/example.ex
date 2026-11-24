defmodule Jido.Examples.SharedBlackboard.Desk do
  @moduledoc "Owns the inventory board for two counters."

  alias Jido.Examples.SharedBlackboard.Counter

  use Jido.Agent,
    name: "shared_blackboard_desk",
    plugins: [{Jido.Plugin.Blackboard.Server, %{name: "inventory", initial: %{"bin-a" => 0}}}]

  topology do
    agent :counters, Counter, count: 2
  end
end

defmodule Jido.Examples.SharedBlackboard.Counter do
  @moduledoc "Reads a count and requests a conditional change to the inventory board."

  alias Jido.Joi
  alias Jido.Plugin.Blackboard.Client
  alias Jido.Plugin.Blackboard.Client.Patch

  defmodule Confirmation do
    @moduledoc "Waits for the result of one inventory update."

    use Jido.Statechart,
      registry: %{guards: %{"confirmed" => {__MODULE__, :confirmed?}, "recheck" => {__MODULE__, :recheck?}}},
      chart: ~SCXML"""
      <scxml xmlns="http://www.w3.org/2005/07/scxml" version="1.0" initial="waiting" datamodel="jido">
        <datamodel>
          <data id="request_id" expr="''"/>
          <data id="outcome" expr="''"/>
        </datamodel>
        <state id="waiting">
          <transition event="jido.blackboard.patch.result" cond="confirmed" target="recorded"/>
          <transition event="jido.blackboard.patch.result" cond="recheck" target="read_again">
            <assign location="outcome" expr="_event.data.status"/>
          </transition>
        </state>
        <final id="recorded"/>
        <final id="read_again"/>
      </scxml>
      """

    def confirmed?(%{data: %{"request_id" => request_id}, event: %{data: result}}) do
      result["request_id"] == request_id and result["status"] == "ok"
    end

    def recheck?(%{data: %{"request_id" => request_id}, event: %{data: result}}) do
      result["request_id"] == request_id and
        result["status"] in ["conflict", "timeout", "unavailable", "indeterminate"]
    end
  end

  use Jido.Agent,
    name: "shared_blackboard_counter",
    plugins: [
      {Client, %{name: "inventory", read_on: ["examples.blackboard.inventory.read"]}},
      {Jido.Plugin.Statechart, %{chart: Confirmation}}
    ]

  state do
    schema Joi.object(%{
             observed_count: Joi.integer() |> Joi.default(0),
             revision: Joi.string() |> Joi.nullable() |> Joi.default(nil)
           })
  end

  routes do
    signal_source "/examples/blackboard/inventory"

    route "examples.blackboard.inventory.read", as: :read do
      action _params, schema: Joi.object(%{}), context: context do
        snapshot = context.plugin_inputs[Client].runtime

        {:ok,
         %{context.agent_state | observed_count: Map.fetch!(snapshot.values, "bin-a"), revision: snapshot.revision}}
      end
    end

    route "examples.blackboard.inventory.count", as: :count do
      action %{count: count, request_id: request_id},
        schema: Joi.object(%{count: Joi.integer() |> Joi.min(0), request_id: Joi.string() |> Joi.min(1)}),
        context: context do
        state = context.agent_state

        if state.revision do
          {:ok, state, [%Patch{revision: state.revision, request_id: request_id, put: %{"bin-a" => count}}]}
        else
          {:error, :read_board_first}
        end
      end
    end

    route "jido.blackboard.patch.result", Jido.Plugin.Statechart.Route
  end
end

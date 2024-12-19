defmodule JidoTest.BasicAgent do
  @moduledoc false
  use Jido.Agent,
    name: "BasicAgent",
    schema: [
      location: [type: :atom, default: :home],
      battery_level: [type: :integer, default: 100]
    ]
end

defmodule JidoTest.SimpleAgent do
  @moduledoc false
  alias Jido.Actions.Basic.{Log, Sleep}

  use Jido.Agent,
    name: "SimpleBot",
    planner: JidoTest.SimpleAgent.Planner,
    runner: JidoTest.SimpleAgent.Runner,
    schema: [
      location: [type: :atom, default: :home],
      battery_level: [type: :integer, default: 100]
    ]

  defmodule Planner do
    @behaviour Jido.Planner

    def plan(_agent, :default, _params) do
      {:ok,
       [
         {Log, message: "Hello, world!"},
         {Sleep, duration: 50},
         {Log, message: "Goodbye, world!"}
       ]}
    end

    def plan(agent, :move, %{location: new_location}) do
      {:ok,
       [
         {Log, message: "Moving from #{agent.location} to #{new_location}..."},
         fn agent ->
           {:ok, %{agent | location: new_location, battery_level: agent.battery_level - 10}}
         end,
         {Log, message: "Arrived at #{new_location}!"}
       ]}
    end

    def plan(_agent, :recharge, _params) do
      {:ok,
       [
         {Log, message: "Recharging battery..."},
         fn agent -> {:ok, %{agent | battery_level: 100}} end,
         {Log, message: "Battery fully charged!"}
       ]}
    end

    def plan(_agent, :custom, %{message: message}) do
      {:ok,
       [
         {Log, message: message},
         {Sleep, duration: 100},
         {Log, message: "Custom command completed"}
       ]}
    end

    def plan(_agent, :sleep, %{duration: duration}) do
      {:ok,
       [
         {Log, message: "Going to sleep..."},
         {Sleep, duration: duration},
         {Log, message: "Waking up!"}
       ]}
    end

    # Fallback for unknown commands
    def plan(_agent, command, _params) do
      {:ok,
       [
         {Log, message: "Unknown command: #{inspect(command)}"},
         {Log, message: "Please use :default, :custom, or :sleep"}
       ]}
    end
  end

  defmodule Runner do
    @behaviour Jido.Runner

    def run(agent, actions, _opts) do
      Jido.Runner.Chain.run(agent, actions)
    end
  end
end

defmodule JidoTest.AdvancedAgent do
  @moduledoc false
  use Jido.Agent,
    name: "AdvancedBot",
    schema: [
      location: [type: :atom, default: :home],
      battery_level: [type: :integer, default: 100],
      has_reported: [type: :boolean, default: false]
    ]

  # def plan(agent, _command \\ :default, _params \\ %{}) do
  #   actions =
  #     cond do
  #       agent.battery_level <= 20 ->
  #         [{Simplebot.Move, destination: :charging_station}, Simplebot.Recharge]

  #       agent.location != :work_area ->
  #         [{Simplebot.Move, destination: :work_area}]

  #       !agent.has_reported ->
  #         [Simplebot.DoWork, Simplebot.Report]

  #       true ->
  #         [Simplebot.Idle]
  #     end

  #   {:ok, actions}
  # end
end

defmodule Jido.Actions.Simplebot do
  @moduledoc """
  A collection of actions for a simple robot simulation.

  This module provides actions for:
  - Move: Simulates moving the robot to a specified location
  - Idle: Simulates the robot idling
  - DoWork: Simulates the robot performing work tasks
  - Report: Simulates the robot reporting its status
  - Recharge: Simulates recharging the robot's battery
  """

  alias Jido.Action

  defmodule Move do
    @moduledoc false
    use Action,
      name: "move_workflow",
      description: "Moves the robot to a specified location",
      schema: [
        destination: [type: :atom, required: true, doc: "The destination location"]
      ]

    @spec run(map(), map()) :: {:ok, map()}
    def run(params, _ctx) do
      # Simulate movement taking between 300-500ms
      Process.sleep(Enum.random(300..500))
      destination = Map.get(params, :destination)
      new_params = Map.put(params, :location, destination)
      {:ok, new_params}
    end
  end

  defmodule Idle do
    @moduledoc false
    use Action,
      name: "idle_workflow",
      description: "Simulates the robot doing nothing"

    @spec run(map(), map()) :: {:ok, map()}
    def run(params, _ctx) do
      # Simulate idling for 100-200ms
      Process.sleep(Enum.random(100..200))
      {:ok, params}
    end
  end

  defmodule DoWork do
    @moduledoc false
    use Action,
      name: "do_work_workflow",
      description: "Simulates the robot performing work tasks"

    @spec run(map(), map()) :: {:ok, map()}
    def run(params, _ctx) do
      # Simulate work taking 1-2 seconds
      Process.sleep(Enum.random(500..1500))
      # Simulating work by decreasing battery level
      decrease = Enum.random(15..25)
      new_params = Map.update(params, :battery_level, 0, &max(0, &1 - decrease))
      {:ok, new_params}
    end
  end

  defmodule Report do
    @moduledoc false
    use Action,
      name: "report_workflow",
      description: "Simulates the robot reporting its status"

    @spec run(map(), map()) :: {:ok, map()}
    def run(params, _ctx) do
      # Simulate reporting taking 200ms
      Process.sleep(200)
      new_params = Map.put(params, :has_reported, true)
      {:ok, new_params}
    end
  end

  defmodule Recharge do
    @moduledoc false
    use Action,
      name: "recharge",
      description: "Simulates recharging the robot's battery"

    @spec run(map(), map()) :: {:ok, map()}
    def run(params, _ctx) do
      # Randomize recharge time between 1-2 seconds
      recharge_time = Enum.random(400..1000)
      # Randomize recharge amount between 20-40%
      recharge_amount = Enum.random(5..25)
      Process.sleep(recharge_time)
      new_params = Map.update(params, :battery_level, 100, &min(100, &1 + recharge_amount))
      {:ok, new_params}
    end
  end
end

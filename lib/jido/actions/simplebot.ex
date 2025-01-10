defmodule Jido.Actions.Simplebot do
  @moduledoc """
  A collection of actions for a simple robot simulation. These are intended to be used as an example and reference for how to write your own bot logic.

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
    def run(params, ctx) do
      # Use context sleep if provided, otherwise random 300-500ms
      sleep_time = Map.get(ctx, :sleep, Enum.random(300..500))
      Process.sleep(sleep_time)
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
    def run(params, ctx) do
      # Use context sleep if provided, otherwise random 100-200ms
      sleep_time = Map.get(ctx, :sleep, Enum.random(100..200))
      Process.sleep(sleep_time)
      {:ok, params}
    end
  end

  defmodule DoWork do
    @moduledoc false
    use Action,
      name: "do_work_workflow",
      description: "Simulates the robot performing work tasks"

    @spec run(map(), map()) :: {:ok, map()}
    def run(params, ctx) do
      # Use context sleep if provided, otherwise random 500-1500ms
      sleep_time = Map.get(ctx, :sleep, Enum.random(500..1500))
      Process.sleep(sleep_time)
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
    def run(params, ctx) do
      # Use context sleep if provided, otherwise 200ms
      sleep_time = Map.get(ctx, :sleep, 200)
      Process.sleep(sleep_time)
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
    def run(params, ctx) do
      # Use context sleep if provided, otherwise random 400-1000ms
      sleep_time = Map.get(ctx, :sleep, Enum.random(400..1000))
      Process.sleep(sleep_time)
      # Always recharge to 100% for predictable behavior
      new_params = Map.put(params, :battery_level, 100)
      {:ok, new_params}
    end
  end
end

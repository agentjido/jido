defmodule Jido.Actions.Basic do
  @moduledoc """
  A collection of basic actions for common workflows.

  This module provides a set of simple, reusable actions:
  - Sleep: Pauses execution for a specified duration
  - Log: Logs a message with a specified level
  - Todo: Logs a todo item as a placeholder or reminder
  - RandomSleep: Introduces a random delay within a specified range
  - Increment: Increments a value by 1
  - Decrement: Decrements a value by 1

  Each action is implemented as a separate submodule and follows the Jido.Action behavior.
  """

  alias Jido.Action

  defmodule Sleep do
    @moduledoc false
    use Action,
      name: "sleep_workflow",
      description: "Sleeps for a specified duration",
      schema: [
        duration_ms: [
          type: :non_neg_integer,
          default: 1000,
          doc: "Duration to sleep in milliseconds"
        ]
      ]

    @spec run(map(), map()) :: {:ok, map()}
    def run(%{duration_ms: duration} = params, _ctx) do
      Process.sleep(duration)
      {:ok, params}
    end
  end

  defmodule Log do
    @moduledoc false
    use Action,
      name: "log_workflow",
      description: "Logs a message with a specified level",
      schema: [
        level: [type: {:in, [:debug, :info, :warning, :error]}, default: :info, doc: "Log level"],
        message: [type: :string, required: true, doc: "Message to log"]
      ]

    require Logger

    @spec run(map(), map()) :: {:ok, map()}
    def run(%{level: level, message: message} = params, _ctx) do
      case level do
        :debug -> Logger.debug(message)
        :info -> Logger.info(message)
        :warning -> Logger.warning(message)
        :error -> Logger.error(message)
      end

      {:ok, params}
    end
  end

  defmodule Todo do
    @moduledoc false
    use Action,
      name: "todo_workflow",
      description: "A placeholder for a todo item",
      schema: [
        todo: [type: :string, required: true, doc: "Todo item description"]
      ]

    require Logger

    @spec run(map(), map()) :: {:ok, map()}
    def run(%{todo: todo} = params, _ctx) do
      Logger.info("TODO Action: #{todo}")
      {:ok, params}
    end
  end

  defmodule RandomSleep do
    @moduledoc false
    use Action,
      name: "random_sleep_workflow",
      description: "Introduces a random sleep within a specified range",
      schema: [
        min_ms: [
          type: :non_neg_integer,
          required: true,
          doc: "Minimum sleep duration in milliseconds"
        ],
        max_ms: [
          type: :non_neg_integer,
          required: true,
          doc: "Maximum sleep duration in milliseconds"
        ]
      ]

    @spec run(map(), map()) :: {:ok, map()}
    def run(%{min_ms: min, max_ms: max} = params, _ctx) do
      delay = Enum.random(min..max)
      Process.sleep(delay)
      {:ok, Map.put(params, :actual_delay, delay)}
    end
  end

  defmodule Increment do
    @moduledoc false
    use Action,
      name: "increment_workflow",
      description: "Increments a value by 1",
      schema: [
        value: [type: :integer, required: true, doc: "Value to increment"]
      ]

    @spec run(map(), map()) :: {:ok, map()}
    def run(%{value: value} = params, _ctx) do
      {:ok, Map.put(params, :value, value + 1)}
    end
  end

  defmodule Decrement do
    @moduledoc false
    use Action,
      name: "decrement_workflow",
      description: "Decrements a value by 1",
      schema: [
        value: [type: :integer, required: true, doc: "Value to decrement"]
      ]

    @spec run(map(), map()) :: {:ok, map()}
    def run(%{value: value} = params, _ctx) do
      {:ok, Map.put(params, :value, value - 1)}
    end
  end
end

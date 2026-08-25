defmodule JidoTest.PluginTestAction do
  @moduledoc false
  use Jido.Action,
    name: "plugin_test_action",
    schema: []

  def run(_params, _context), do: {:ok, %{}}
end

defmodule JidoTest.PluginTestAnotherAction do
  @moduledoc false
  use Jido.Action,
    name: "plugin_test_another_action",
    schema: Zoi.object(%{value: Zoi.integer() |> Zoi.default(0)})

  def run(%{value: value}, _context), do: {:ok, %{value: value}}
end

defmodule JidoTest.NotAnActionModule do
  @moduledoc false
  def some_function, do: :ok
end

defmodule JidoTest.TestActions do
  @moduledoc """
  Shared test actions for Jido test suite.
  """

  alias Jido.Action
  alias Jido.Agent.{Directive, StateOp}

  defmodule BasicAction do
    @moduledoc false
    use Action,
      name: "basic_action",
      description: "A basic action for testing",
      schema: Zoi.object(%{value: Zoi.integer()})

    def run(%{value: value}, _context) do
      {:ok, %{value: value}}
    end
  end

  defmodule NoSchema do
    @moduledoc false
    use Action,
      name: "no_schema",
      description: "Action with no schema"

    def run(%{value: value}, _context), do: {:ok, %{result: value + 2}}
    def run(_params, _context), do: {:ok, %{result: "No params"}}
  end

  defmodule Add do
    @moduledoc false
    use Action,
      name: "add",
      description: "Adds amount to value",
      schema:
        Zoi.object(%{
          value: Zoi.integer(),
          amount: Zoi.integer() |> Zoi.default(1)
        })

    def run(%{value: value, amount: amount}, _context) do
      {:ok, %{value: value + amount}}
    end
  end

  defmodule EmitAction do
    @moduledoc false
    use Action,
      name: "emit_action",
      description: "Action that returns an emit effect"

    def run(_params, _context) do
      signal = %{type: "test.emitted", data: %{value: 42}}
      {:ok, %{emitted: true}, Directive.emit(signal)}
    end
  end

  defmodule MultiEffectAction do
    @moduledoc false
    use Action,
      name: "multi_effect_action",
      description: "Action that returns multiple effects"

    def run(_params, _context) do
      effects = [
        Directive.emit(%{type: "event.1"}),
        Directive.schedule(1000, :check)
      ]

      {:ok, %{triggered: true}, effects}
    end
  end

  defmodule SetStateAction do
    @moduledoc false
    use Action,
      name: "set_state_action",
      description: "Action that uses StateOp.SetState"

    def run(_params, _context) do
      {:ok, %{primary: "result"}, %StateOp.SetState{attrs: %{extra: "state"}}}
    end
  end

  defmodule ReplaceStateAction do
    @moduledoc false
    use Action,
      name: "replace_state_action",
      description: "Action that uses StateOp.ReplaceState"

    def run(_params, _context) do
      {:ok, %{}, %StateOp.ReplaceState{state: %{replaced: true, fresh: "state"}}}
    end
  end

  defmodule DeleteKeysAction do
    @moduledoc false
    use Action,
      name: "delete_keys_action",
      description: "Action that uses StateOp.DeleteKeys"

    def run(_params, _context) do
      {:ok, %{}, %StateOp.DeleteKeys{keys: [:to_delete, :also_delete]}}
    end
  end

  defmodule SetPathAction do
    @moduledoc false
    use Action,
      name: "set_path_action",
      description: "Action that uses StateOp.SetPath"

    def run(_params, _context) do
      {:ok, %{}, %StateOp.SetPath{path: [:nested, :deep, :value], value: 42}}
    end
  end

  defmodule DeletePathAction do
    @moduledoc false
    use Action,
      name: "delete_path_action",
      description: "Action that uses StateOp.DeletePath"

    def run(_params, _context) do
      {:ok, %{}, %StateOp.DeletePath{path: [:nested, :to_remove]}}
    end
  end

  defmodule IncrementAction do
    @moduledoc "Action that increments the :counter state field"
    use Action,
      name: "increment",
      schema: Zoi.object(%{amount: Zoi.integer() |> Zoi.default(1)})

    def run(%{amount: amount}, context) do
      count = Map.get(context.state, :counter, 0)
      {:ok, %{counter: count + amount}}
    end
  end

  defmodule DecrementAction do
    @moduledoc "Action that decrements the :counter state field"
    use Action,
      name: "decrement",
      schema: Zoi.object(%{amount: Zoi.integer() |> Zoi.default(1)})

    def run(%{amount: amount}, context) do
      count = Map.get(context.state, :counter, 0)
      {:ok, %{counter: count - amount}}
    end
  end

  defmodule RecordAction do
    @moduledoc "Action that appends params to the :messages state field"
    use Action,
      name: "record",
      schema: Zoi.object(%{message: Zoi.any() |> Zoi.optional()})

    def run(params, context) do
      messages = Map.get(context.state, :messages, [])
      message = Map.get(params, :message, params)
      {:ok, %{messages: messages ++ [message]}}
    end
  end

  defmodule SlowAction do
    @moduledoc "Action that sleeps for a configurable delay"
    use Action,
      name: "slow",
      schema: Zoi.object(%{delay_ms: Zoi.integer() |> Zoi.default(100)})

    def run(%{delay_ms: delay}, _context) do
      Process.sleep(delay)
      {:ok, %{processed: true, delay: delay}}
    end
  end

  defmodule FailingAction do
    @moduledoc "Action that always fails with a configurable error message"
    use Action,
      name: "failing",
      schema:
        Zoi.object(%{
          reason: Zoi.string() |> Zoi.default("intentional failure")
        })

    def run(%{reason: reason}, _context) do
      {:error, reason}
    end
  end
end

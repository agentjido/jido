#!/usr/bin/env elixir

# CalculatorAgent Demo Script
# This script demonstrates the CalculatorAgent with skills defined in default_opts

# Load the project
Mix.install([
  {:jido, path: "."}
])

# Load our calculator agent
Code.require_file("lib/agents/calculator_agent.ex")

defmodule CalculatorDemo do
  require Logger

  def run do
    Logger.info("🧮 Starting CalculatorAgent Demo")
    Logger.info("======================================")

    # Start the calculator agent
    {:ok, pid} = CalculatorAgent.start_link(name: :demo_calculator)
    Logger.info("✅ Started CalculatorAgent with PID: #{inspect(pid)}")

    # Demonstrate basic calculations
    Logger.info("\n📊 Testing Basic Calculations:")
    test_calculation(pid, "2 + 2")
    test_calculation(pid, "10 * 5")
    test_calculation(pid, "sqrt(16)")
    test_calculation(pid, "sin(pi/2)")
    test_calculation(pid, "(3 + 4) * 2")

    # Check calculation count
    Logger.info("\n📈 Testing Count & History:")
    {:ok, count} = CalculatorAgent.count(pid)
    Logger.info("Total calculations: #{count}")

    # Get calculation history
    {:ok, history} = CalculatorAgent.history(pid)
    Logger.info("History entries: #{length(history)}")
    
    Enum.with_index(history, 1)
    |> Enum.each(fn {calc, index} ->
      Logger.info("  #{index}. #{calc.expression} = #{calc.result}")
    end)

    # Test error handling
    Logger.info("\n⚠️  Testing Error Handling:")
    test_calculation(pid, "1 / 0")
    test_calculation(pid, "invalid_expression")

    # Test clearing history
    Logger.info("\n🧹 Testing Clear History:")
    :ok = CalculatorAgent.clear(pid)
    {:ok, new_count} = CalculatorAgent.count(pid)
    {:ok, new_history} = CalculatorAgent.history(pid)
    Logger.info("After clear - Count: #{new_count}, History: #{length(new_history)} entries")

    # Test more calculations after clear
    Logger.info("\n🔄 Testing After Clear:")
    test_calculation(pid, "100 / 4")
    test_calculation(pid, "cos(0)")

    {:ok, final_count} = CalculatorAgent.count(pid)
    Logger.info("Final count: #{final_count}")

    Logger.info("\n✅ Demo completed successfully!")
    Logger.info("======================================")
    
    # Stop the agent
    GenServer.stop(pid)
    
    :ok
  end

  defp test_calculation(pid, expression) do
    case CalculatorAgent.calculate(pid, expression) do
      {:ok, result} ->
        Logger.info("  ✅ #{expression} = #{result}")
        
      {:error, reason} ->
        Logger.warn("  ❌ #{expression} failed: #{inspect(reason)}")
    end
  end
end

# Run the demo
CalculatorDemo.run()

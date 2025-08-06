#!/usr/bin/env elixir

# Enhanced Iterator Demo Script
# This script demonstrates the enhanced Chain of Thought pattern using the Iterator action
# with body actions and decision actions for flexible control flow

Mix.install([
  {:jido, path: "."}
])

defmodule IteratorDemo do
  @moduledoc """
  Demo script showing the enhanced Iterator action with body and decision actions.
  """

  def run do
    IO.puts("🔄 Enhanced Iterator Demo - Chain of Thought with Body & Decision Actions")
    IO.puts("=" |> String.duplicate(70))

    # Create the Iterator agent
    agent = Jido.Agents.IteratorAgent.new([])
    IO.puts("✅ IteratorAgent created with ID: #{agent.id}")
    IO.puts("")

    # Demo 1: Simple iteration (backward compatibility)
    demo_simple_iteration(agent)
    IO.puts("")

    # Demo 2: Advanced iteration with decision action
    demo_advanced_iteration(agent)
    IO.puts("")

    # Demo 3: Counting iteration that stops at a limit
    demo_counting_iteration(agent)
    
    IO.puts("")
    IO.puts("🎉 All demos completed! The enhanced Iterator action provides:")
    IO.puts("   • Body actions execute custom logic at each iteration")
    IO.puts("   • Decision actions control when to continue or stop")
    IO.puts("   • State accumulation across iterations")
    IO.puts("   • Multiple termination conditions for safety")
    IO.puts("👋 Demo finished")
  end

  defp demo_simple_iteration(agent) do
    IO.puts("📌 Demo 1: Simple Iteration (Backward Compatibility)")
    IO.puts("   Using CounterBody to increment a counter each step")
    
    {:ok, final_agent, []} = Jido.Agents.IteratorAgent.start_simple_iteration(agent, 5)
    
    IO.puts("   ✅ Instructions enqueued: #{:queue.len(final_agent.pending_instructions)}")
    IO.puts("   📋 This will run 5 iterations, incrementing count by 1 each time")
    
    # Peek at the instruction parameters
    {{:value, instruction}, _queue} = :queue.out(final_agent.pending_instructions)
    IO.puts("   🔧 Body Action: #{inspect(instruction.params.body_action)}")
    IO.puts("   ⚙️  Body Params: #{inspect(instruction.params.body_params)}")
  end

  defp demo_advanced_iteration(agent) do
    IO.puts("📌 Demo 2: Advanced Iteration with Decision Control")
    IO.puts("   Using LimitDecision to stop when count reaches 20")
    
    opts = [
      max_steps: 50,  # High safety limit
      body_params: %{increment: 3},
      decision_params: %{count_limit: 20}
    ]
    
    {:ok, final_agent, []} = Jido.Agents.IteratorAgent.start_advanced_iteration(agent, opts)
    
    IO.puts("   ✅ Instructions enqueued: #{:queue.len(final_agent.pending_instructions)}")
    IO.puts("   📋 This will increment by 3 each step until count reaches 20")
    
    # Peek at the instruction parameters
    {{:value, instruction}, _queue} = :queue.out(final_agent.pending_instructions)
    IO.puts("   🔧 Body Action: #{inspect(instruction.params.body_action)}")
    IO.puts("   🧠 Decision Action: #{inspect(instruction.params.decision_action)}")
    IO.puts("   ⚙️  Decision Params: #{inspect(instruction.params.decision_params)}")
  end

  defp demo_counting_iteration(agent) do
    IO.puts("📌 Demo 3: Counting Iteration with Custom Parameters")
    IO.puts("   Counting to 15 with increments of 4")
    
    {:ok, final_agent, []} = Jido.Agents.IteratorAgent.start_counting_iteration(agent, 15, 4)
    
    IO.puts("   ✅ Instructions enqueued: #{:queue.len(final_agent.pending_instructions)}")
    IO.puts("   📋 This will increment by 4 each step until count reaches 15")
    
    # Peek at the instruction parameters
    {{:value, instruction}, _queue} = :queue.out(final_agent.pending_instructions)
    IO.puts("   🔧 Increment: #{instruction.params.body_params.increment}")
    IO.puts("   🎯 Count Limit: #{instruction.params.decision_params.count_limit}")
    IO.puts("   🛡️  Safety Limit: #{instruction.params.max_steps} steps")
  end
end

# Custom body action demo
defmodule FibonacciBodyDemo do
  @moduledoc """
  Example of a custom body action that calculates Fibonacci sequence
  """
  use Jido.Action,
    name: "fibonacci_body",
    description: "Calculates next Fibonacci number"

  def run(params, _context) do
    step = params[:step] || 0
    iterator_state = params[:iterator_state] || %{}
    
    # Get previous two Fibonacci numbers
    prev1 = iterator_state[:fib_prev1] || 1
    prev2 = iterator_state[:fib_prev2] || 0
    
    # Calculate next Fibonacci number
    next_fib = prev1 + prev2
    
    result = %{
      step: step,
      fibonacci: next_fib,
      sequence: (iterator_state[:sequence] || [0, 1]) ++ [next_fib]
    }
    
    # Return new state for next iteration
    {:ok, %{
      fib_prev1: next_fib,
      fib_prev2: prev1,
      sequence: result.sequence,
      current_fibonacci: next_fib
    }}
  end
end

# Custom decision action demo
defmodule FibonacciLimitDecision do
  @moduledoc """
  Example decision action that stops when Fibonacci number exceeds a limit
  """
  use Jido.Action,
    name: "fibonacci_limit_decision",
    description: "Stops when Fibonacci exceeds limit"

  def run(params, _context) do
    iterator_state = params[:iterator_state] || %{}
    limit = params[:limit] || 100
    current_fib = iterator_state[:current_fibonacci] || 0
    
    continue = current_fib < limit
    
    {:ok, %{
      continue: continue,
      current_fibonacci: current_fib,
      limit: limit,
      message: if continue do
        "Continue: #{current_fib} < #{limit}"
      else
        "Stop: #{current_fib} >= #{limit}"
      end
    }}
  end
end

defmodule CustomIteratorDemo do
  @moduledoc """
  Demo showing custom body and decision actions
  """
  
  def run do
    IO.puts("")
    IO.puts("🌟 Bonus Demo: Custom Fibonacci Iterator")
    IO.puts("=" |> String.duplicate(50))
    
    # Create agent with custom actions  
    defmodule FibonacciAgent do
      use Jido.Agent,
        name: "FibonacciAgent",
        actions: [
          Jido.Actions.Iterator,
          FibonacciBodyDemo,
          FibonacciLimitDecision
        ]
    end
    
    agent = FibonacciAgent.new([])
    
    # Start Fibonacci iteration that stops when number exceeds 50
    params = %{
      max_steps: 20,  # Safety limit
      body_action: FibonacciBodyDemo,
      decision_action: FibonacciLimitDecision,
      decision_params: %{limit: 50},
      state: %{
        fib_prev1: 1,
        fib_prev2: 0,
        sequence: [0, 1]
      }
    }
    
    {:ok, final_agent, []} = FibonacciAgent.cmd(
      agent,
      {Jido.Actions.Iterator, params},
      %{},
      runner: Jido.Runner.Simple
    )
    
    IO.puts("✅ Fibonacci iterator started!")
    IO.puts("📋 This will calculate Fibonacci numbers until one exceeds 50")
    IO.puts("🔢 Starting sequence: [0, 1]")
    IO.puts("🎯 Stop condition: Fibonacci number > 50")
    IO.puts("📝 Instructions enqueued: #{:queue.len(final_agent.pending_instructions)}")
  end
end

# Run all demos
IteratorDemo.run()
CustomIteratorDemo.run()

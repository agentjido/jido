#!/usr/bin/env elixir

# Demo script comparing SimpleAgent vs EasyAgent (Agent.Server-backed)
# Run with: elixir examples/easy_agent_demo.exs

Mix.install([
  {:jido, path: "#{__DIR__}/../"}
])

defmodule EasyAgentDemo do
  @moduledoc """
  Demonstrates the developer experience differences between:
  1. Jido.SimpleAgent (original simple implementation)
  2. Jido.EasyAgent (SimpleAgent API on Agent.Server foundation)
  """

  require Logger

  def run_demo do
    IO.puts("\n" <> String.duplicate("=", 60))
    IO.puts("JIDO AGENT COMPARISON DEMO")
    IO.puts(String.duplicate("=", 60))
    
    demo_simple_agent()
    demo_easy_agent()
    compare_apis()
    
    IO.puts("\n" <> String.duplicate("=", 60))
    IO.puts("DEMO COMPLETE - Check logs above for comparison")
    IO.puts(String.duplicate("=", 60))
  end

  def demo_simple_agent do
    IO.puts("\n📱 SIMPLE AGENT DEMO")
    IO.puts(String.duplicate("-", 40))
    
    try do
      # Start SimpleAgent
      IO.puts("Starting SimpleAgent...")
      {:ok, pid} = Jido.SimpleAgent.start_link(
        name: "simple_demo",
        actions: [Jido.Skills.Arithmetic.Actions.Eval]
      )
      IO.puts("✅ SimpleAgent started (PID: #{inspect(pid)})")
      
      # Test basic conversation
      IO.puts("\n🗣️  Testing conversation...")
      {:ok, response} = Jido.SimpleAgent.call(pid, "Hello!")
      IO.puts("User: Hello!")
      IO.puts("Bot:  #{response}")
      
      # Test math capability
      IO.puts("\n🧮 Testing math...")
      {:ok, response} = Jido.SimpleAgent.call(pid, "5 + 3")
      IO.puts("User: 5 + 3")
      IO.puts("Bot:  #{response}")
      
      # Test memory
      IO.puts("\n🧠 Checking memory...")
      {:ok, memory} = Jido.SimpleAgent.get_memory(pid)
      IO.puts("Messages in memory: #{length(memory.messages)}")
      
      IO.puts("✅ SimpleAgent demo completed successfully!")
      
    rescue
      error ->
        IO.puts("❌ SimpleAgent demo failed: #{inspect(error)}")
    end
  end

  def demo_easy_agent do
    IO.puts("\n🏭 EASY AGENT (Agent.Server-backed) DEMO")
    IO.puts(String.duplicate("-", 40))
    
    try do
      # Start EasyAgent  
      IO.puts("Starting EasyAgent...")
      {:ok, pid} = Jido.EasyAgent.start_link(
        name: "easy_demo",
        actions: [Jido.Skills.Arithmetic.Actions.Eval]
      )
      IO.puts("✅ EasyAgent started (PID: #{inspect(pid)})")
      
      # Test basic conversation
      IO.puts("\n🗣️  Testing conversation...")
      {:ok, response} = Jido.EasyAgent.call(pid, "Hello!")
      IO.puts("User: Hello!")
      IO.puts("Bot:  #{response}")
      
      # Test math capability
      IO.puts("\n🧮 Testing math...")
      {:ok, response} = Jido.EasyAgent.call(pid, "5 + 3")
      IO.puts("User: 5 + 3")
      IO.puts("Bot:  #{response}")
      
      # Test action registration
      IO.puts("\n🔧 Testing action registration...")
      :ok = Jido.EasyAgent.register_action(pid, Jido.Tools.Basic.Log)
      IO.puts("✅ Registered Log action successfully")
      
      IO.puts("✅ EasyAgent demo completed successfully!")
      
    rescue
      error ->
        IO.puts("❌ EasyAgent demo failed: #{inspect(error)}")
        IO.puts("Error details: #{Exception.format(:error, error)}")
    end
  end

  def compare_apis do
    IO.puts("\n🔍 API COMPARISON")
    IO.puts(String.duplicate("-", 40))
    
    IO.puts("SimpleAgent API:")
    IO.puts("  {:ok, pid} = SimpleAgent.start_link(name: \"demo\")")
    IO.puts("  {:ok, response} = SimpleAgent.call(pid, \"message\")")
    IO.puts("  SimpleAgent.register_action(pid, SomeAction)")
    
    IO.puts("\nEasyAgent API:")
    IO.puts("  {:ok, pid} = EasyAgent.start_link(name: \"demo\")")
    IO.puts("  {:ok, response} = EasyAgent.call(pid, \"message\")")
    IO.puts("  EasyAgent.register_action(pid, SomeAction)")
    
    IO.puts("\n💡 Identical APIs, but EasyAgent uses Agent.Server under the hood!")
    IO.puts("   This means you get all the production benefits with simple DX.")
  end

  def show_todos do
    IO.puts("\n📋 CURRENT TODOs IN EASYAGENT IMPLEMENTATION")
    IO.puts(String.duplicate("-", 40))
    
    todos = [
      "Auto-generate Agent modules dynamically (currently uses RuntimeAgent)",
      "Proper conversation history management via Agent.Server state updates", 
      "Real instruction execution via Agent.Server (currently simulated)",
      "Better error handling and recovery mechanisms",
      "Support for multi-turn conversations with proper state management",
      "Integration with Agent.Server's signal emission for observability",
      "Memory management (clear_memory, get_memory functions)",
      "Timeout and cancellation support",
      "Better reasoner integration with Agent.Server's lifecycle"
    ]
    
    todos
    |> Enum.with_index(1)
    |> Enum.each(fn {todo, idx} ->
      IO.puts("#{idx}. #{todo}")
    end)
  end
end

# Run the demo
EasyAgentDemo.run_demo()
EasyAgentDemo.show_todos()

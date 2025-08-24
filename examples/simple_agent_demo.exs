# Simple demonstration of the Jido.SimpleAgent implementation
# Run this with: mix run examples/simple_agent_demo.exs

alias Jido.SimpleAgent

# Start an agent with arithmetic capabilities
{:ok, pid} = SimpleAgent.start_link(
  name: "demo_agent",
  actions: [Jido.Skills.Arithmetic.Actions.Eval]
)

IO.puts "=== Jido SimpleAgent Demo ==="
IO.puts ""

# Demo conversations
conversations = [
  {"Hello", "Basic greeting"},
  {"What can you do?", "Capability inquiry"},
  {"What is 2 + 3?", "Simple math"},
  {"Calculate 10 * 5 + 15", "Complex math"},
  {"What is the weather?", "Non-math query"},
  {"Thank you", "Gratitude"},
  {"Goodbye", "Farewell"}
]

Enum.each(conversations, fn {message, description} ->
  IO.puts "#{description}: \"#{message}\""
  
  case SimpleAgent.call(pid, message) do
    {:ok, response} ->
      IO.puts "Response: #{response}"
    {:error, reason} ->
      IO.puts "Error: #{inspect(reason)}"
  end
  
  IO.puts ""
end)

# Show memory state
{:ok, memory} = SimpleAgent.get_memory(pid)

IO.puts "=== Final Memory State ==="
IO.puts "Messages: #{length(memory.messages)}"
IO.puts "Tool Results: #{map_size(memory.tool_results)}"

IO.puts ""
IO.puts "Conversation History:"
Enum.with_index(memory.messages, 1)
|> Enum.each(fn {message, index} ->
  role = String.upcase(to_string(message.role))
  content = case message.content do
    content when is_binary(content) -> content
    content -> inspect(content)
  end
  
  name_part = if Map.has_key?(message, :name) and message.name do
    " (#{message.name})"
  else
    ""
  end
  
  IO.puts "  #{index}. #{role}#{name_part}: #{String.slice(content, 0, 80)}..."
end)

if map_size(memory.tool_results) > 0 do
  IO.puts ""
  IO.puts "Tool Results:"
  Enum.each(memory.tool_results, fn {action, result} ->
    IO.puts "  #{action}: #{inspect(result)}"
  end)
end

IO.puts ""
IO.puts "Demo completed successfully! Steps 4-5 of SimpleAgent are implemented:"
IO.puts "✓ Action Registration & Discovery"
IO.puts "✓ Tool Execution Phase" 
IO.puts "✓ Complete Agent Loop Integration"
IO.puts "✓ Memory Management"
IO.puts "✓ Error Handling"

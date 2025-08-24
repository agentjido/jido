# Jido.SimpleAgent Implementation Plan

## Overview

Build a lightweight, runtime-configurable GenServer that implements the Strands agent loop pattern:

**receive input → reason → decide → execute tools → incorporate results → respond**

This is a simpler alternative to `Jido.Agent` focused on runtime configuration and clear agent loop semantics.

## Architecture Goals

- **Simple**: No compile-time macros, runtime configuration only
- **Compatible**: Uses existing `Jido.Action` system as tools
- **Progressive**: Each step builds cleanly on the previous
- **Extensible**: Hook points for LLM integration and custom reasoners

## Implementation Steps

### Step 1: Foundation & Scaffolding
**Deliverable**: Basic GenServer that can start and echo responses

**Files to create:**
- `lib/jido/simple_agent.ex` - Main GenServer implementation
- `test/jido/simple_agent_test.exs` - Test suite
- `examples/simple_agent_demo.exs` - Runnable demonstration

**API:**
```elixir
# Basic GenServer operations
{:ok, pid} = Jido.SimpleAgent.start_link(name: "demo_agent")
{:ok, response} = Jido.SimpleAgent.call(pid, "Hello")
# Returns: {:ok, "Echo: Hello"}
```

**State structure:**
```elixir
%{
  id: String.t(),
  name: String.t(), 
  actions: [module()],
  memory: %{messages: [], tool_results: %{}},
  turn: 0,
  max_turns: 10
}
```

### Step 2: Memory & Message Management
**Deliverable**: Agent tracks conversation history and manages message flow

**Features:**
- Message history in memory with roles (`:user`, `:assistant`, `:tool`)
- Memory access methods for debugging and inspection
- Message flow validation

**API additions:**
```elixir
{:ok, memory} = Jido.SimpleAgent.get_memory(pid)
:ok = Jido.SimpleAgent.clear_memory(pid)
```

### Step 3: Rule-Based Reasoner (LLM Stub)
**Deliverable**: Simple pattern-matching reasoner that can detect tool needs

**Files to create:**
- `lib/jido/simple_agent/reasoner.ex` - Behaviour definition
- `lib/jido/simple_agent/rule_based_reasoner.ex` - Pattern-matching implementation

**Enhanced Reasoning Logic:**
```elixir
# Math Detection - routes to Eval action for any mathematical expression
~r/(?:what\s+is|calculate|compute|solve)\s*(.+?)(?:\?|$)/i → 
  {:tool_call, Jido.Skills.Arithmetic.Actions.Eval, %{expression: captured_expr}}

# 10 Basic Text Response Patterns:
~r/^(?:hi|hello|hey)/i → {:respond, "Hello! How can I help you?"}
~r/help|what\s+can\s+you\s+do/i → {:respond, "I can help with math calculations and answer basic questions."}
~r/thank|thx/i → {:respond, "You're welcome!"}
~r/bye|goodbye|see\s+you/i → {:respond, "Goodbye! Have a great day!"}
~r/what\s+(?:is\s+)?(?:your\s+)?name/i → {:respond, "I'm a Jido SimpleAgent!"}
~r/what\s+time/i → {:respond, "I don't have access to the current time, but I can help with calculations!"}
~r/weather/i → {:respond, "I can't check the weather, but I'm great with math!"}
~r/how\s+are\s+you|status/i → {:respond, "I'm running smoothly and ready to help!"}
~r/what\s+(?:can\s+)?you\s+do/i → {:respond, "I can perform mathematical calculations and have basic conversations."}
# Default fallback → {:respond, "I'm not sure about that, but I can help with math calculations!"}
```

### Step 4: Action Registration & Discovery
**Deliverable**: Agent can register and validate Jido.Actions as available tools

**Features:**
- Dynamic action registration at runtime
- Action validation using existing `Jido.Util.validate_actions/1`
- Tool discovery for reasoner decision-making

**API additions:**
```elixir
:ok = Jido.SimpleAgent.register_action(pid, Jido.Skills.Arithmetic.Actions.Add)
{:ok, actions} = Jido.SimpleAgent.list_actions(pid)
```

### Step 5: Tool Execution Phase
**Deliverable**: Agent can execute registered actions and handle results

**Features:**
- Action execution using `Action.run/2` 
- Result capture in memory
- Error handling for action failures
- Tool result context for next reasoning cycle

**Flow:**
1. Reasoner returns `{:tool_call, action_module, params}`
2. Validate action is registered
3. Execute `action_module.run(params, context)`
4. Store result in `memory.tool_results`
5. Add tool message to conversation history

### Step 6: Complete Agent Loop
**Deliverable**: Full agent loop with multi-turn reasoning

**Features:**
- Turn tracking and max_turns protection
- Recursive reasoning after tool execution
- Loop termination conditions
- Complete conversation flow

**Flow Example:**
```
User: "What is 2 + 3 and then multiply by 4?"
Turn 1: Reason → {:tool_call, Add, %{value: 2, amount: 3}}
        Execute → {:ok, %{result: 5}}
        Reason → {:tool_call, Multiply, %{value: 5, amount: 4}}  
Turn 2: Execute → {:ok, %{result: 20}}
        Reason → {:respond, "The answer is 20"}
Response: "The answer is 20"
```

### Step 7: Error Handling & Resilience
**Deliverable**: Comprehensive error handling with proper error types

**Error categories:**
```elixir
{:error, {:reasoner, reason}} # Reasoner failures
{:error, {:tool_validation, action, reason}} # Invalid action or params
{:error, {:tool_execution, action, reason}} # Action runtime errors
{:error, {:loop, :max_turns_exceeded}} # Loop protection
{:error, {:state, reason}} # State management errors
```

**Recovery strategies:**
- Failed tool calls can trigger fallback responses
- State validation errors reset to clean state
- Reasoner errors trigger safe default responses

### Step 8: Configuration & Customization
**Deliverable**: Flexible configuration system

**Configuration options:**
```elixir
Jido.SimpleAgent.start_link([
  name: "my_agent",
  actions: [Jido.Skills.Arithmetic.Actions.Add, Jido.Skills.Arithmetic.Actions.Multiply],
  reasoner: Jido.SimpleAgent.RuleBasedReasoner,
  max_turns: 15,
  memory_limit: 100 # messages
])
```

**Customization points:**
- Pluggable reasoner modules
- Configurable action lists
- Memory management policies
- Turn limits and timeouts

### Step 9: Integration & Polish
**Deliverable**: Production-ready module with docs and examples

**Features:**
- Complete documentation with examples
- Integration with existing Jido patterns
- Performance optimizations
- Comprehensive test coverage
- Dialyzer type specifications

**Testing scenarios:**
- Single tool calls
- Multi-turn conversations
- Error recovery
- Memory management
- Concurrent agent instances

## Key Design Decisions

### 1. GenServer vs Functional
GenServer provides natural state management and message handling for the agent loop.

### 2. Runtime vs Compile-time Configuration  
Runtime configuration enables dynamic agent creation with different tool sets.

### 3. Reasoner Abstraction
Behavior allows swapping rule-based reasoner for LLM later without changing core loop.

### 4. Memory Structure
Simple message list + tool results map provides clear conversation tracking.

### 5. Action Integration
Reuse existing `Jido.Action` system - no need to reinvent tool calling.

## Success Criteria

Each step should be:
1. **Runnable**: Can be tested independently
2. **Demonstrable**: Clear example of new functionality  
3. **Documented**: API and behavior clearly explained
4. **Tested**: Unit tests verify expected behavior
5. **Incremental**: Builds clearly on previous step

Final result: A simple agent that demonstrates the Strands agent loop using Jido.Actions as tools, with clear progression from basic echo to sophisticated multi-turn tool usage.

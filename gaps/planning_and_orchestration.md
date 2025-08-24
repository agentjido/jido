# Gap Analysis: Planning and Orchestration Capabilities

## Overview

SimpleAgent and Agent.Server represent fundamentally different approaches to action planning and execution orchestration, with significant implications for workflow complexity and determinism.

## SimpleAgent: Runtime-Only Decision Making

### Planning Model
```elixir
defp reason_and_act(state) do
  last_message = get_last_message(state.memory)
  
  case state.reasoner.reason(last_message, state) do
    {:respond, response} -> {:respond, response, state}
    {:tool_call, action_module, params} -> execute_tool(action_module, params, state)
  end
end
```

### Characteristics
- **Just-in-Time Planning**: Decisions made during execution loop
- **Single Action Focus**: Only one action per reasoning cycle
- **Reasoner-Driven**: External reasoner module determines next action
- **No Persistence**: Plans exist only in reasoner logic, not stored
- **Immediate Execution**: Action runs as soon as decided

### Limitations
- Cannot pre-plan multi-step workflows
- No dependency management between actions
- No ability to inspect or modify planned actions
- No support for conditional branching in plans
- No persistence of execution intent

## Agent.Server: Explicit Instruction Planning

### Planning Model
```elixir
# Multi-action planning with persistence
{:ok, agent} = MyAgent.plan(agent, [
  ValidateAction,
  {ProcessAction, %{file: "data.csv"}},
  {SaveAction, %{path: "/tmp"}}
], %{request_id: "abc123"})

# Plans stored as Instructions in pending_instructions queue
%Agent{
  pending_instructions: #Queue<[
    %Instruction{action: ValidateAction, params: %{}, context: %{request_id: "abc123"}},
    %Instruction{action: ProcessAction, params: %{file: "data.csv"}, context: %{request_id: "abc123"}},
    %Instruction{action: SaveAction, params: %{path: "/tmp"}, context: %{request_id: "abc123"}}
  ]>
}
```

### Characteristics
- **Ahead-of-Time Planning**: Instructions queued before execution
- **Multi-Action Support**: Can plan complex workflows
- **Persistent Plans**: Instructions survive across process restarts
- **Runner Abstraction**: Pluggable execution strategies
- **Context Propagation**: Shared context across related actions

### Capabilities
- Dependency management through runners
- Plan inspection and modification before execution
- Rollback and replay of instruction sequences
- Parallel execution strategies
- Conditional execution based on previous results

## Key Orchestration Differences

| Feature | SimpleAgent | Agent.Server |
|---------|-------------|--------------|
| **Planning Horizon** | Single turn | Multi-step workflows |
| **Plan Storage** | None (in reasoner logic) | Persistent instruction queue |
| **Execution Strategy** | Sequential only | Pluggable (simple/parallel/chain) |
| **Context Sharing** | Via memory only | Explicit context propagation |
| **Plan Modification** | Not supported | Instructions can be inspected/modified |
| **Dependency Management** | Not supported | Runner-dependent |
| **Rollback/Replay** | Not supported | Full instruction history |

## Runner System Comparison

### SimpleAgent: No Runner Abstraction
```elixir
# Direct action execution
case action_module.run(params, context) do
  {:ok, result} -> {:continue, updated_state}
  {:error, reason} -> {:respond, error_response, state}
end
```

### Agent.Server: Pluggable Runners
```elixir
# Multiple execution strategies available
runner: Jido.Runner.Simple      # Sequential execution
runner: Jido.Runner.Parallel    # Concurrent execution  
runner: Jido.Runner.Chain       # Pipeline execution
runner: CustomRunner            # Domain-specific logic
```

## Real-World Implications

### SimpleAgent Scenarios
```elixir
# Good: Interactive Q&A
"What's 2+2?" → Reasoner decides math → Execute Eval → "4"

# Limited: Multi-step workflow
"Process this file" → Can only do one action at a time
                   → No way to plan validate→process→save sequence
```

### Agent.Server Scenarios
```elixir
# Excellent: Complex workflows
MyAgent.plan(agent, [
  {ValidateFile, %{path: "/data.csv"}},
  {ProcessFile, %{path: "/data.csv"}},  
  {GenerateReport, %{format: :pdf}},
  {EmailReport, %{to: "user@domain.com"}}
])
# All planned upfront, executed with error handling/retries
```

## Gap Assessment

### Critical Gaps in SimpleAgent
1. **No Workflow Planning**: Cannot handle multi-step business processes
2. **No Execution Strategies**: Stuck with sequential-only execution
3. **No Plan Persistence**: Cannot survive process restarts
4. **No Dependency Management**: Cannot handle action prerequisites
5. **No Context Propagation**: Limited data sharing between actions

### Architectural Trade-offs
- SimpleAgent's lack of planning is **intentional** for its use case
- The gap represents different design philosophies, not missing features
- Each system optimizes for different operational requirements

## Bridging Recommendations

1. **Introduce Planning Interface**: Add optional `plan/2` to SimpleAgent that pre-computes action sequences
2. **Add Runner Support**: Allow SimpleAgent to use lightweight runners for multi-action scenarios  
3. **Context Enhancement**: Improve memory system to support workflow-style context propagation
4. **Instruction Compatibility**: Make SimpleAgent able to consume Agent.Server instruction formats

## Conclusion

The planning gap reflects the systems' different purposes:
- **SimpleAgent**: Optimized for reactive, conversation-driven interactions
- **Agent.Server**: Optimized for proactive, workflow-driven automation

Both approaches are valid; the gap analysis helps users choose the right tool for their specific orchestration needs.

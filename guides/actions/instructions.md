# Instructions and Targets

This guide shows how to name what Exec runs. A target is an Action or a Flow. A `Jido.Instruction` is a value that binds one target to its parameters, context, and metadata.

## Target forms

`Jido.Exec.run/4` accepts four target forms. All of them use the same validation and result contract.

| Target | Kind | Example |
|---|---|---|
| Action module | `:action` | `Tickets.CloseTicket` |
| Flow module | `:flow` | `Tickets.TriageFlow` |
| Runtime `Jido.Flow` value | `:flow` | `Tickets.TriageFlow.flow()` |
| `Jido.Instruction` | Its target's kind | `Jido.Instruction.new!(target: Tickets.CloseTicket)` |

```elixir
defmodule Tickets.CloseTicket do
  use Jido.Action,
    name: "close_ticket",
    schema: Jido.Joi.object(%{ticket_id: Jido.Joi.string()})

  @impl true
  def run(params, context), do: {:ok, Map.put(params, :closed_by, context[:user_id])}
end

defmodule Tickets.TriageFlow do
  use Jido.Flow,
    name: "triage_flow",
    schema: Jido.Joi.object(%{ticket_id: Jido.Joi.string()})

  flow do
    step "close", action: Tickets.CloseTicket, params: %{ticket_id: input(:ticket_id)}
    output result("close")
  end
end

params = %{ticket_id: "t-1"}

expected = %{ticket_id: "t-1", closed_by: nil}
{:ok, ^expected} = Jido.Exec.run(Tickets.CloseTicket, params)
{:ok, ^expected} = Jido.Exec.run(Tickets.TriageFlow, params)
{:ok, ^expected} = Jido.Exec.run(Tickets.TriageFlow.flow(), params)
{:ok, ^expected} = Jido.Exec.run(Jido.Instruction.new!(target: Tickets.CloseTicket), params)
```

Jido classifies a module by its declared behaviour. Callback names alone do not make a module a target. A module that implements both `Jido.Action` and `Jido.Flow` is an error. So is a module that does not load.

## Build an Instruction

`Jido.Instruction.new/1` takes a keyword list or a map with atom keys. `Jido.Instruction.new!/1` raises the same error instead of returning it.

```elixir
{:ok, instruction} =
  Jido.Instruction.new(
    target: Tickets.CloseTicket,
    params: %{ticket_id: "t-1"},
    context: [user_id: "u-9"],
    metadata: %{request_id: "req-7"}
  )

%Jido.Instruction{
  kind: :action,
  target: Tickets.CloseTicket,
  params: %{ticket_id: "t-1"},
  context: %{user_id: "u-9"},
  metadata: %{request_id: "req-7"}
} = instruction

{:ok, %{ticket_id: "t-1", closed_by: "u-9"}} = Jido.Exec.run(instruction)
```

| Field | Input | Purpose |
|---|---|---|
| `:target` | Required | Any target form in the table above |
| `:params` | Map, keyword list, or `nil` | Input for the target. It is validated when the target runs. |
| `:context` | Map, keyword list, or `nil` | Caller data for the target. See [Action Context](action-context.md). |
| `:metadata` | Map, keyword list, or `nil` | Annotation. It has no meaning to the target or to Exec. |
| `:kind` | Optional, `:action` or `:flow` | A check. It must match the current target. |

An Instruction does not hold execution policy. Pass `:timeout` and other options to Exec. See [Execution Policy](action-execution-policy.md).

The fields `:id`, `:action`, `:flow`, and `:opts` are not supported and return an error:

```elixir
{:error, %Jido.Error.ValidationError{details: %{reason: :removed_instruction_fields, fields: [:action]}}} =
  Jido.Instruction.new(action: Tickets.CloseTicket)
```

## Merge call data

Call-site values replace equal top-level keys of a stored Instruction. Merges are shallow, so a nested map is replaced as a whole. `Jido.Exec.run/4` applies this rule through `Jido.Instruction.resolve/3`.

```elixir
stored =
  Jido.Instruction.new!(
    target: Tickets.CloseTicket,
    params: %{ticket_id: "t-1", labels: %{priority: "high"}},
    context: %{user_id: "u-1"},
    metadata: %{request_id: "req-7"}
  )

{:ok, resolved} =
  Jido.Instruction.resolve(stored, %{labels: %{team: "support"}}, %{user_id: "u-2", tenant: "acme"})

%{ticket_id: "t-1", labels: %{team: "support"}} = resolved.params
%{user_id: "u-2", tenant: "acme"} = resolved.context
%{request_id: "req-7"} = resolved.metadata

{:ok, %{closed_by: "u-2"}} = Jido.Exec.run(stored, %{}, %{user_id: "u-2"})
```

A target can itself be an Instruction. `Jido.Instruction.new/1` flattens it. Outer params, context, and metadata replace equal inner keys.

```elixir
wrapped = Jido.Instruction.new!(target: stored, params: %{ticket_id: "t-2"}, metadata: %{attempt: 2})

%Jido.Instruction{
  target: Tickets.CloseTicket,
  params: %{ticket_id: "t-2", labels: %{priority: "high"}},
  metadata: %{request_id: "req-7", attempt: 2}
} = wrapped
```

## Check a target

`Jido.Instruction.validate/1` resolves a target or an Instruction and confirms its callbacks. It does not run work. An Action needs `run/2`, and a Flow module needs `flow/0`. Both need `validate_params/1` and `validate_output/1`.

```elixir
:ok = Jido.Instruction.validate(Tickets.CloseTicket)
:ok = Jido.Instruction.validate(stored)

{:error, %Jido.Error.ValidationError{details: %{target: String, reason: :missing_behaviour}}} =
  Jido.Instruction.validate(String)
```

Resolution reads the current module on every execution. A stored `kind` is not trusted after a code reload. A declared kind that disagrees with the module fails with `reason: :target_kind_changed`.

## Separate declaration from call data

`Jido.Instruction.template/3` records a module and a kind without loading the module. Use it when the target may not be available yet, for example at compile time. It takes an optional metadata map, and it holds no params or context.

`Jido.Instruction.bind/4` adds call data. It loads the module, checks the declared kind and callbacks, and merges runtime metadata over template metadata.

```elixir
template = Jido.Instruction.template(:action, Tickets.CloseTicket, %{source: "router"})

{:ok, bound} =
  Jido.Instruction.bind(template, %{ticket_id: "t-3"}, %{user_id: "u-3"}, %{request_id: "req-8"})

%{source: "router", request_id: "req-8"} = bound.metadata
{:ok, %{ticket_id: "t-3", closed_by: "u-3"}} = Jido.Exec.run(bound)

{:error, %Jido.Error.ValidationError{details: %{reason: :target_kind_changed}}} =
  Jido.Instruction.bind(Jido.Instruction.template(:flow, Tickets.CloseTicket), %{}, %{})
```

`Jido.Instruction.bind/4` is stricter than `Jido.Instruction.new/1`. Its context and metadata must be maps. Keyword lists return an error. It also does not check `params`, so pass a map when you will give the result to `Jido.Exec.run/4`, which rejects any other value.

## Where each form is accepted

| Position | Accepts |
|---|---|
| `Jido.Exec.run/4`, `Jido.Exec.compile/2`, `Jido.Durable.start/4` | All four forms |
| Invoke expander, `{:continue, input, target}` | Action module, Flow module, `Jido.Flow` value, or Instruction |
| Handoff selector, `{:handoff, input, target}` | Any target with no bound context or metadata |
| Flow step `:action` | Action or Flow module. A bound Instruction is rejected. |

Exec also returns an Instruction. A terminal Handoff produces `{:handoff, instruction, effects}` and does not run the successor. Pass that Instruction to `Jido.Exec.run/4` when your code is ready. See [Dynamic Flows](../flows/dynamic-flows.md).

## Storage

An Instruction is a runtime value. It has no JSON form, because module atoms and runtime Flow values do not have one general JSON form. To store a Flow, see [Store Flows as JSON](../flow-data/flow-storage.md).

## Related

- [Actions](actions.md)
- [Action Context](action-context.md)
- Definitions and Runtime

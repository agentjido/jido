# Flow Data Definitions

This reference lists every field that `Jido.Flow.new/1` accepts.
Use it when your code assembles a Flow as a map. For the module DSL, see the field reference in `Jido.Flow`.

## Definition

`Jido.Flow.new/1` returns `{:ok, flow}` or `{:error, exception}`. `Jido.Flow.new!/1` returns the Flow or raises the same exception.

```elixir
defmodule TicketFlows.Classify do
  use Jido.Action, name: "classify_ticket"

  @impl true
  def run(%{subject: subject}, _context) do
    {:ok, %{queue: if(subject =~ "refund", do: "billing", else: "support")}}
  end
end

defmodule TicketFlows.Assign do
  use Jido.Action, name: "assign_ticket"

  @impl true
  def run(%{queue: queue}, _context), do: {:ok, %{assigned_to: queue <> "-team"}}
end

alias Jido.Flow.Ref

ticket_flow =
  Jido.Flow.new!(%{
    name: "route_ticket",
    description: "Classify a ticket and assign its queue",
    schema: Jido.Joi.object(%{subject: Jido.Joi.string()}),
    components: [
      %{
        kind: :step,
        name: "classify",
        action: TicketFlows.Classify,
        params: %{subject: Ref.input(:subject)}
      },
      %{
        kind: :step,
        name: "assign",
        action: TicketFlows.Assign,
        params: %{queue: Ref.result("classify", :queue)}
      }
    ],
    output: Ref.result("assign")
  })

{:ok, %{assigned_to: "billing-team"}} =
  Jido.Exec.run(ticket_flow, %{subject: "refund request"})
```

| Key | Required | Default | Rule |
| --- | --- | --- | --- |
| `:name` | Yes | None | A non-blank UTF-8 string of at most 256 bytes. An atom is rejected. |
| `:components` | Yes | None | A non-empty proper list of component maps. |
| `:output` | Yes | None | A non-nil Flow value. |
| `:description` | No | `nil` | A string or `nil`. |
| `:schema` | No | `Jido.Joi.map()` | The input schema. It must be a map-shaped Joi schema. |
| `:output_schema` | No | `Jido.Joi.map()` | The output schema. It must be a map-shaped Joi schema. |

Any other key is an error. There is no `:id` or `:vsn` key. Those options belong to Flow modules, as [Flow Identity](flow-identity-and-versioning.md) explains.

Construction accepts any non-nil `:output` value, but Flow output must be a map at run time. A literal such as `42` builds and then fails when the Flow runs.

## Common component fields

Every component takes these fields:

| Field | Required | Default | Rule |
| --- | --- | --- | --- |
| `:kind` | Yes | None | One of the kinds below. |
| `:name` | Yes | None | A non-blank string or atom. An atom becomes a string. Names are unique in the Flow. |
| `:needs` | No | `[]` | Names of components that must finish first. Duplicates are rejected. |
| `:meta` | No | `%{}` | A plain map of portable data. It cannot hold references or expressions. |

Unknown fields are errors. The kinds `:timer`, `:await`, and `:selection` become one `:wait` component kind in the canonical value.

## Component kinds

In the tables below, a call means an `:action` target and optional `:params`. `:params` defaults to `%{}`. Each `:action` is a module atom.

### Step

Runs one Action.

| Field | Required | Rule |
| --- | --- | --- |
| `:action` | Yes | An Action module. |
| `:params` | No | A Flow value. |

### Subflow

Runs one Flow module as a nested call. The target must be a module, not a `Jido.Flow` value.

| Field | Required | Rule |
| --- | --- | --- |
| `:flow` | Yes | A Flow module. |
| `:params` | No | A Flow value. |

### Choice

Runs the first option whose condition is true, or the fallback. See [Choices and Conditions](../flows/flow-choices.md).

| Field | Required | Rule |
| --- | --- | --- |
| `:options` | Yes | A non-empty list. Each option has a unique `:name`, a `:condition`, and a call. |
| `:fallback` | Yes | A map with `:action` and optional `:params`. No other field is allowed. |

A `:condition` is a Boolean, a `Jido.Flow.Ref`, or a `Jido.Expr` operation.

### Map

Calls one Action for each collection item. See [Map and Reduce](../flows/flow-collections.md).

| Field | Required | Default | Rule |
| --- | --- | --- | --- |
| `:collection` | Yes | None | A Flow value. |
| `:action` | Yes | None | An Action module. |
| `:params` | No | `%{}` | A Flow value. It can use item references. |
| `:on_error` | No | `:fail_fast` | `:fail_fast` or `:collect_errors`. |

### Reduce

Calls one Action for each item and threads an accumulator.

| Field | Required | Rule |
| --- | --- | --- |
| `:collection` | Yes | A Flow value. |
| `:initial` | Yes | A Flow value. |
| `:action` | Yes | An Action module. |
| `:params` | No | A Flow value. It can use item and accumulator references. |

### Parallel

Runs named Action calls side by side.

| Field | Required | Default | Rule |
| --- | --- | --- | --- |
| `:actions` | Yes | None | A non-empty list. Each entry has a unique `:name` and a call. |
| `:on_error` | No | `:fail_fast` | `:fail_fast` or `:collect_errors`. |

### Iterate

Repeats one Action and updates a state value. See [Iterate and State](../flows/flow-iterate-state.md).

| Field | Required | Rule |
| --- | --- | --- |
| `:action` | Yes | An Action module. |
| `:params` | No | A Flow value. |
| `:state` | Yes | A map with required `:initial` and `:update` values, and an optional `:schema` that defaults to `Jido.Joi.map()`. |
| `:completion` | Yes | A condition. |
| `:max_iterations` | Yes | An integer from 1 to 10,000. |

### Invoke

Runs a decision Action and passes its result to an expander. See [Dynamic Flows](../flows/dynamic-flows.md).

| Field | Required | Rule |
| --- | --- | --- |
| `:decision` | Yes | An Action module. |
| `:expander` | Yes | An Action module. It takes no `:params` of its own. |
| `:params` | No | A Flow value for the decision. |

### Handoff

Finishes the current Flow and requests a new Turn. A Flow can have one Handoff. It must be the final component, so nothing can depend on it, and the Flow output must be `Jido.Flow.Ref.result/2` of that component with no path.

| Field | Required | Rule |
| --- | --- | --- |
| `:selector` | Yes | An Action module. |
| `:params` | No | A Flow value. |

### Timer, await, and selection

These kinds pause a Flow. See Flow Waits.

| Kind | Field | Required | Rule |
| --- | --- | --- | --- |
| `:timer` | `:after_ms` | Yes | A non-negative integer. |
| `:await` | `:event` | Yes | A non-empty string. |
| `:await` | `:match` | No | A Flow value. Defaults to `%{}`. |
| `:selection` | `:options` | Yes | A non-empty list of `:timer` and `:await` maps, each with its own `:kind` and a unique `:name`. |

A `:timer` rejects `:event` and `:match`. An `:await` rejects `:after_ms`.

### Example with several kinds

```elixir
alias Jido.Flow.Ref

triage =
  Jido.Flow.new!(%{
    name: "triage_tickets",
    components: [
      %{
        kind: :map,
        name: "classified",
        collection: Ref.input(:tickets),
        action: TicketFlows.Classify,
        params: %{subject: Ref.item(:subject)},
        on_error: :collect_errors
      },
      %{
        kind: :choice,
        name: "escalation",
        needs: ["classified"],
        meta: %{owner: "support-ops"},
        options: [
          %{
            name: "urgent",
            condition: Jido.Expr.new!(:==, [Ref.input(:priority), "high"]),
            action: TicketFlows.Assign,
            params: %{queue: "on-call"}
          }
        ],
        fallback: %{action: TicketFlows.Assign, params: %{queue: "support"}}
      },
      %{kind: :timer, name: "cool_down", after_ms: 60_000, needs: ["escalation"]}
    ],
    output: %{assignment: Ref.result("escalation")}
  })

%{kind: :map, on_error: :collect_errors} = triage.components["classified"]
%{kind: :wait, options: [%{name: "cool_down", after_ms: 60_000}]} = triage.components["cool_down"]
```

## Flow values

`:params`, `:output`, `:collection`, `:initial`, and similar fields hold a Flow value. A Flow value is one of these:

- a portable scalar: `nil`, a Boolean, a number, a valid UTF-8 string, or an atom;
- a proper list of Flow values;
- a plain map of Flow values, with string, atom, or non-negative integer keys;
- a `Jido.Flow.Ref`;
- a `Jido.Expr` operation.

A value tree can hold up to 256 levels and 100,000 nodes. Each expression also has the smaller limits from `Jido.Expr`. See [Expressions](../flows/flow-expressions.md).

## References

Build references with `Jido.Flow.Ref`. A path argument is one key, or a list of atoms, strings, and non-negative integers. `Jido.Flow.Ref.select/2` appends to an existing reference.

| Function | Reads | Valid in |
| --- | --- | --- |
| `Jido.Flow.Ref.input/1` | Flow input. `input([])` reads all of it. | Any Flow value |
| `Jido.Flow.Ref.context/1` | Runtime context | Any Flow value |
| `Jido.Flow.Ref.result/2` | A named component result. Also adds a dependency. | Any Flow value |
| `Jido.Flow.Ref.item/1` | The current item | Map and Reduce `:params` |
| `Jido.Flow.Ref.item_index/0` | The item index | Map and Reduce `:params` |
| `Jido.Flow.Ref.item_id/0` | The item identifier | Map and Reduce `:params` |
| `Jido.Flow.Ref.accumulator/1` | The accumulator | Reduce `:params` |
| `Jido.Flow.Ref.state/1` | Iterate state | Iterate `:params`, `:update`, and `:completion` |
| `Jido.Flow.Ref.iteration_index/0` | The iteration index | Iterate `:params`, `:update`, and `:completion` |
| `Jido.Flow.Ref.body_result/1` | The Iterate body result | Iterate `:params`, `:update`, and `:completion` |

See [References and Data](../flows/flow-references.livemd) for how paths resolve at run time.

## Validation errors

Construction returns a `Jido.Error.ValidationError`. It reports the first problem, and `details.path` locates it in your definition.

```elixir
alias Jido.Flow.Ref

{:error, unknown_reference} =
  Jido.Flow.new(%{
    name: "route_ticket",
    components: [
      %{
        kind: :step,
        name: "assign",
        action: TicketFlows.Assign,
        params: %{queue: Ref.result("classify", :queue)}
      }
    ],
    output: Ref.result("assign")
  })

"Flow reference points to an unknown component" = Exception.message(unknown_reference)
%{path: [:components, 0], component: "classify"} = unknown_reference.details
```

| Message | Cause |
| --- | --- |
| `expected a Jido.Flow artifact` | The argument is not a plain map. |
| `unknown Flow configuration key: :id` | The definition has an unsupported key. |
| `Flow must declare at least one component` | `:components` is empty. |
| `Flow output is required` | `:output` is missing or `nil`. |
| `unknown Flow field: :retries` | A component has an unsupported field. |
| `expected a supported Flow component kind` | `:kind` is missing or unknown. |
| `data authoring uses :step or :subflow for a call` | The definition uses the canonical `:call` kind. |
| `duplicate component name` | Two components have one name. |
| `Flow reference points to an unknown component` | A `result` reference names no component. |
| `flow dependency graph contains a cycle` | `:needs` and result references form a loop. |
| `flow expression contains a scoped ref outside its valid scope` | A reference is outside the fields listed in the references table. |
| `invalid Flow expression` | A value is a function, a tuple, or another unsupported term. |
| `Flow target must be a module atom` | A target is a tuple, a string, or `nil`. |

## Canonical structure

`Jido.Flow.new/1` lowers your definition to a canonical struct:

- `components` becomes a map keyed by component name.
- `:step` and `:subflow` become `kind: :call` with a `call` map of `kind`, `target`, and `params`.
- Every default is filled in.

```elixir
%{
  kind: :call,
  call: %{kind: :action, target: TicketFlows.Classify, params: _params},
  needs: [],
  meta: %{}
} = ticket_flow.components["classify"]
```

`Jido.Flow.validate/1` checks this exact canonical shape. It does not accept authoring shortcuts, so use `Jido.Flow.new/1` to build a Flow and `Jido.Flow.validate/1` to recheck one you already have. Neither function loads a target or runs an Action.

## Related

- [Authoring Runtime Data](authoring-runtime-data.md) shows how to build a definition safely.
- [Flow Dependencies](../flows/flow-dependencies.livemd) explains `:needs` and result references.

# Optimization ideas rejected by source inspection

These are contract or cost-path checks, not measured speed improvements.
The first inspection used runtime `99b92e80`. The later rows below used `6b999a4e`. No runtime change was retained for these
ideas. The accepted measurement procedure remains in the 50-round plan.

| Round | Source and finding | Decision |
| ---: | --- | --- |
| 03 | `Thread.append/2` starts sequence numbers from `length(thread.entries)`. The public struct and schema accept caller-supplied `entries` and `stats` independently. For two entries and a cached count of 9, the current next sequence is 2, while the proposed cache path would use 9. | Reject the cached base count. It changes accepted value behavior. |
| 04 | `Thread.slice/3` filters all entries. The schema accepts a list of arbitrary entries and does not enforce sequence order. For sequence values `[4, 1, 3]`, a slice from 1 through 3 returns the last two entries. Stopping at the first value above 3 loses both. | Reject early stopping without a new ordered-value contract. |
| 15 | `Agent.State.defaults_from_schema/1` already uses one `Enum.reduce/3`. It inserts only default fields and parses each such field once. There is no separate extraction list or second default pass to fuse. | Reject this proposed pass fusion. Keep default parsing. |
| 35 | `Agent.default_checkpoint/2` calls `definition/1` once. That function clears two fields in a small Agent struct; it does not rebuild routes or schemas. State is stored separately. Public `checkpoint/2` validates the current caller-supplied value and invokes the configured callback. | Reject definition caching at this boundary. No repeated definition construction exists in the default checkpoint. |
| 37 | `Persistence.save_agent/3` builds one checkpoint record and calls `encode_record/1` once. The expected CAS value is the original binary returned by the adapter; it is not re-encoded. The portability and current-record checks serve different validation boundaries. | Reject removal of a repeated checkpoint encoding; it is absent. Keep the CAS and portability checks. |
| 38 | `AgentServer.call/3` already has a direct timeout clause. The default call uses that clause and supplies an empty context. Only the keyword form uses the option schema, once. | Reject a new default-option fast path; it already exists. Keep keyword validation. |
| 40 | `ActiveTurn.mark_committed/3` already clears the caller, Exec handle, and prepared command. `AgentServer.complete_outcome/2` clears the active Turn on completion and failure. The remaining source/effective Signals and Turn context are needed for directives and the public Outcome until completion. | Reject early removal of those required fields. The large prepared command already releases at commit. |
| 41 | OTP retains each postponed event once. `AgentServer.remember_postponed/2` stores only its token in a `MapSet`; it does not retain another Signal or context. Tokens are removed on admission or expiry. | Reject duplicate-context removal; no second queued context exists in Server state. |
| 43 | `AgentServer.snapshot/2` returns the complete committed Agent and its version. That process transfer is part of its public result. `status/2` already returns phase, counts, IDs, versions, and runtime information without complete domain state. `plugin_state/3` selects one Plugin state value. | Reject shrinking the snapshot result. Use the existing smaller APIs when they satisfy the caller's need. |
| 49 | `Topology.Plan` resolves each Agent's input state and each resource configuration during plan construction. `Controller.Activation` receives that resolved state. It fetches each subscription's bus ID from the prepared context and does not repeat `Reference.resolve/3`. | Reject a second reference cache in activation. The proposed repeated resolution is already outside that path. |

These decisions reject the stated hypotheses. They do not rule out a different
design with an explicit contract change. This cycle preserves the v3 contracts.

## Later inspection

| Round | Source and finding | Decision |
| ---: | --- | --- |
| 19 | `Command.Runner.do_prepare/4` calls `Map.merge/2` once, with the caller context and three reserved values. `Command.normalize_context/1` returns a plain map unchanged. There is no chain of full context maps to remove. Keyword input requires one conversion. | Reject removal of intermediate full context maps; they are absent. The key-list cost was handled in Round 18. |
| 23 | `Plugin.apply_state_updates/2` gets owned directives with `Enum.filter/2`. With `[]`, it returns `[]` without visiting any item or creating groups. `update_state/3` must still run: Plugins such as the turn counter can update state with no directives. | Reject a new empty grouping path and skipping reducers. There are no groups to remove, and reducers are required. |
| 32 | `Registry.identifier/3` compares values with `==`. A Registry holding `{:value, %URI{port: 1}}` resolves a query for `%URI{port: 1.0}` to the same ID. A reverse map uses exact key equality and misses that query. `Registry.new/1` accepts the input. A local runtime probe confirmed both results. | Reject a direct reverse-map replacement. It changes accepted numeric-equivalent lookups. Numeric normalization or an indexed fallback would be a separate design. |
| 44 | `AgentServer.handle_event/4` matches `[directive \| rest]`. `continue_directives/3` passes that same `rest` tail into the next internal event. It does not append, reverse, or rebuild the remaining directive list. The reply-action append joins at most one reply with one continuation event. | Reject continuation-list copy removal; no full tail copy is present in this path. |
| 46 | `SpanCtx.tracer_module` already stores the selected tracer across start, stop, and exception callbacks. Failure mode is read on failure, so a runtime configuration change during a span can change warn/strict handling. Caching that value at start changes this behavior. | Reject further configuration caching across the span. The duplicate start work is a separate Round 45 idea. |
| 48 | Durable scheduler state stores `pending` and `last_scheduled_at`. Admission compares the complete pending payload; acknowledgement finds the occurrence ID; queueing uses the last time to suppress repeats, including after acknowledgement. `Delivery.deliver/3` already creates its fresh Signal only in the delivery task. No retry attempt Signal is retained in durable state. | Reject removal of these progress fields. They are recovery and duplicate-control data, not stored transient delivery data. |

Round 32 probe on Elixir 1.20.3 / OTP 29:

```elixir
registry = Registry.new!(%{"integer" => {:value, %URI{port: 1}}})
Registry.identifier(registry, :value, %URI{port: 1.0}) # {:ok, "integer"}
reverse = Map.new(registry.entries, fn {id, entry} -> {entry, id} end)
Map.fetch(reverse, {:value, %URI{port: 1.0}}) # :error
```

## Map and state checks

These checks used runtime `3e58775f` and Elixir 1.20.3 / OTP 29.

| Round | Source and finding | Decision |
| ---: | --- | --- |
| 12 | `DeepMerge` passes plain maps to `Map.merge/3`, which calls `:maps.merge_with/3`. The runtime iterates the smaller map. With an empty right map, `merge_with_1(none, Result, _)` returns the left map. No map entries or conflict callback are visited. | Reject a second empty-right copy-avoidance path. The runtime already returns the existing map. Preserve the separate struct replacement branch. |
| 13 | The same runtime path selects the empty left map as its iterator and returns the right map directly. It does not traverse or copy the right map. | Reject a second empty-left copy-avoidance path. There is no full-map cost to remove. No speed gain is claimed for either empty-map idea. |
| 25 | `Plugin.apply_state_updates/2` parses reducer output even when it equals the input. A static integer increment transform changes an unchanged reducer value from 1 to 2. `Map.put/3` then shares that validated value; it does not deep-copy the nested value. The possible large traversal is schema parsing, whose effects must run. | Reject skipping the parse for unchanged owned state. The attached probe confirms the required transform. |
| 26 | `Agent.Validation.validate_routes/1` calls `Authoring.routes/1`. That function normalizes each route once and returns the list. It does not call `Router.new/1`. The default command handler constructs its router once later. | Reject reuse of a router within Agent validation; no router is constructed there. Server reuse is still a separate pending idea. |
| 30 | Command preparation parses the current state. `Agent.transition/2` later parses the prior state and the proposed state. A static integer-to-string transform can make that prior state fail its second parse. A probe confirms that the Action runs before this error. Public transition also must reject an invalid prior Agent. | Reject dropping this state traversal under the current behavior contract. Schema composition reuse is a separate pending idea. |

`docs/performance/probes/validation-effects.exs` checks Rounds 25 and 30.
The map findings were read from the loaded `Map` and `:maps` BEAM abstract code.
These checks do not supply timing evidence.

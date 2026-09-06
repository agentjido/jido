# Optimization ideas rejected by source inspection

These are contract or cost-path checks, not measured speed improvements.
The inspected runtime is `99b92e80`. No runtime change was retained for these
ideas. The accepted measurement procedure remains in the 50-round plan.

| Round | Source and finding | Decision |
| ---: | --- | --- |
| 03 | `Thread.append/2` starts sequence numbers from `length(thread.entries)`. The public struct and schema accept caller-supplied `entries` and `stats` independently. For two entries and a cached count of 9, the current next sequence is 2, while the proposed cache path would use 9. | Reject the cached base count. It changes accepted value behavior. |
| 04 | `Thread.slice/3` filters all entries. The schema accepts a list of arbitrary entries and does not enforce sequence order. For sequence values `[4, 1, 3]`, a slice from 1 through 3 returns the last two entries. Stopping at the first value above 3 loses both. | Reject early stopping without a new ordered-value contract. |
| 15 | `Agent.State.defaults_from_schema/1` already uses one `Enum.reduce/3`. It inserts only default fields and parses each such field once. There is no separate extraction list or second default pass to fuse. | Reject this proposed pass fusion. Keep default parsing. |
| 35 | `Agent.default_checkpoint/2` calls `definition/1` once. That function clears two fields in a small Agent struct; it does not rebuild routes or schemas. State is stored separately. Public `checkpoint/2` validates the current caller-supplied value and invokes the configured callback. | Reject definition caching at this boundary. No repeated definition construction exists in the default checkpoint. |
| 38 | `AgentServer.call/3` already has a direct timeout clause. The default call uses that clause and supplies an empty context. Only the keyword form uses the option schema, once. | Reject a new default-option fast path; it already exists. Keep keyword validation. |
| 40 | `ActiveTurn.mark_committed/3` already clears the caller, Exec handle, and prepared command. `AgentServer.complete_outcome/2` clears the active Turn on completion and failure. The remaining source/effective Signals and Turn context are needed for directives and the public Outcome until completion. | Reject early removal of those required fields. The large prepared command already releases at commit. |
| 41 | OTP retains each postponed event once. `AgentServer.remember_postponed/2` stores only its token in a `MapSet`; it does not retain another Signal or context. Tokens are removed on admission or expiry. | Reject duplicate-context removal; no second queued context exists in Server state. |
| 43 | `AgentServer.snapshot/2` returns the complete committed Agent and its version. That process transfer is part of its public result. `status/2` already returns phase, counts, IDs, versions, and runtime information without complete domain state. `plugin_state/3` selects one Plugin state value. | Reject shrinking the snapshot result. Use the existing smaller APIs when they satisfy the caller's need. |

These decisions reject the stated hypotheses. They do not rule out a different
design with an explicit contract change. This cycle preserves the v3 contracts.

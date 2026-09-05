# V2 removal and replacement decisions

The approved V3 source is the implementation contract. The file register in
`legacy-dispositions.json` records every old `lib` and `test` file before removal.
It includes each old test name and public function name for the M12 audit.
An assigned replacement is not a claim that its acceptance check has passed.

The cutover removes these public V2 contracts:

| V2 contract | V3 use and limit |
| --- | --- |
| Action/instruction `cmd`, Strategy, StateOp | Send a Signal to an Action or Flow. Return a complete candidate state. Direct success is `{:ok, agent, directives}`. |
| Plugin manifests, requirements, mounts and old callbacks | Declare the V3 Plugin Spec. Use `prepare`, `admit`, owned state and owned directives. Preserve the implemented callback order. |
| DirectiveExec protocol and built-in lifecycle/status Actions | Use the V3 runtime directives and explicit application Actions. Custom executors require a port. |
| Sensor callbacks and cron directives | Use input Plugins, Heartbeat, SensorManager and Scheduler. The old Sensor callback interface is removed. |
| Persist, Storage and Thread stores | Use Persistence adapters and the Agent envelope. Old stored data requires an explicit application conversion. No automatic conversion is supplied. |
| InstanceManager attachment and idle policies; worker pools | Use instance startup, child ownership and explicit bounded workers. Automatic idle eviction, attachment and pre-warmed pools are removed. |
| Pod and live Pod mutation | Use child ownership, application group recovery and static Topology. Live mutation has no equivalent in this release. |
| Await facade and old status fields | Use AgentServer request results, cancellation and inspection. Application completion remains an application contract. |
| Discovery | No V3 discovery service is supplied. Explicit module lists replace discovery where needed. |
| Identity profile/evolution and integrated Memory | Applications own identity policy and history in state. Security examples do not replace the old profile or multi-space Memory interfaces. |
| Thread Agent/Plugin integration | Keep standalone Thread values. Applications own history, compaction and persistence. |
| Old observation/configuration internals | Use V3 lifecycle, Turn, commit and directive events. Event consumers must use the V3 fields. |

The old source remains in Git at the recorded core baseline. Its tests are not
left as excluded files in the active suite. The register names the behavior
checks that replace them. M12 must check the retained safety obligations:
state validation and isolation, safe errors, partition scope, storage faults,
ownership, shutdown, timers, and state-size limits from current main.

No source-compatible adapter is added for an interface whose old state or
callback contract no longer exists. This is an intentional major-version change.

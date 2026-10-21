---
modules:
  - Jido.Instance.Options
  - Jido.Instance.NamespaceRegistry
  - Jido.Instance.RefFacade
---

## Purpose

Protect Jido instance configuration, supervision identity, namespaces, Agent
lifecycle selection, and stable Agent Ref routing. The public `Jido` and
generated instance functions are facades for this component. AgentServer Turn
behavior, persistence record meaning, and downstream operation results stay
with their owning components.

## Obligations

### jido.instance.I1 — Instance definition and validation

- **scope:** `use Jido`, `Jido.child_spec/1`, `Jido.start_link/1`
- **must:** Merge application configuration with runtime overrides, keep the generated module as the instance name, and validate the complete option set before any child starts. Reject non-keyword input, unknown keys, missing or invalid names, invalid namespaces, debug levels, Task limits, AgentServer defaults, and persistence sources with a structured instance configuration error.
- **why:** An invalid instance must not create a partial runtime tree.
- **kind:** functional
- **status:** active

### jido.instance.I2 — Supervision identity and lifetime

- **scope:** `Jido.start/1`, `Jido.start_link/1`, `Jido.child_spec/1`, `Jido.stop/1`
- **must:** Start one named supervisor with instance-scoped Runner, Task Supervisor, registration guard, Registry, RuntimeStore, and Agent Supervisor children. Derive stable child names from the instance name. Support use as a child specification. Make convenience startup idempotent without changing the first live configuration. Wait for old named children to stop before replacement startup.
- **why:** Separate instances must not share process ownership or reuse a stopping child.
- **kind:** functional
- **status:** active

### jido.instance.I3 — Namespace ownership

- **scope:** `Jido.start_link/1`, `Jido.namespace/1`
- **must:** Bind an optional nonempty namespace to at most one live local instance. Keep the exact binding while that instance is live, release an unbound claim after failed startup, remove the binding after owner loss, and restore live bindings after the namespace registry worker restarts.
- **why:** A stable Ref namespace must identify one current local instance without becoming stuck after failure.
- **kind:** functional
- **status:** active

### jido.instance.I4 — Fixed instance runtime defaults

- **scope:** generated instance `config/1`, `Jido.instance_persistence/1`, `Jido.instance_agent_server_options/1`
- **must:** Apply runtime options after application and declared defaults. Store the validated persistence source and AgentServer defaults for the live instance. Keep those selected values fixed for that lifetime and available across RuntimeStore worker replacement.
- **why:** Consumers need one stable set of instance defaults.
- **kind:** functional
- **status:** active

### jido.instance.I5 — Agent lifecycle selection

- **scope:** `Jido.start_agent/3`, `Jido.stop_agent/3`, `Jido.whereis_agent/3`, `Jido.list_agents/2`, `Jido.agent_count/2`
- **must:** Route lifecycle functions through the selected instance and exact partition. Isolate equal Agent IDs across instances and partitions. List and count only the selected partition. Reject a PID operation whose explicit partition does not match its registration. Generated and default-instance wrappers must select the same functions.
- **why:** Instance and partition selection must not target another activation.
- **kind:** functional
- **status:** active

### jido.instance.I6 — Stable Ref construction

- **scope:** `Jido.agent_ref/3`, `Jido.start_agent_ref/4`, `Jido.activate_agent/4`
- **must:** Build a Ref only from a live stable namespace, exact Agent ID, and optional partition. Keep process and storage data out of the Ref. Reject malformed Refs, unknown options, namespace mismatch, and startup identity conflicts before starting work. Preserve the same Ref identity when its namespace later binds to another local instance.
- **why:** Stable identity must not depend on one process or local instance name.
- **kind:** functional
- **status:** active

### jido.instance.I7 — Ref resolution

- **scope:** `Jido.resolve_agent/2`
- **must:** Resolve the exact namespace, partition, and Agent ID through the selected instance Registry. Return the ready AgentServer PID, `not_found` when no matching worker is registered, `recovering` while the matching worker is not ready, and `unavailable` when the Registry or a resolved worker is lost. Resolve each operation again after worker replacement and do not replay work.
- **why:** A stable Ref must not retain or reuse a stale PID.
- **kind:** functional
- **status:** active

### jido.instance.I8 — Ref operation routing

- **scope:** `Jido.call/4`, `Jido.cast/3`, `Jido.submit/4`, committed reads, controls, and generated instance Ref functions
- **must:** Route each supported Ref function to the currently resolved AgentServer and preserve its public result and caller-wait contract. Support submit, await, and abandon wrappers. Return an explicit error for a missing target. Keep caller timeout separate from execution cancellation.
- **why:** A Ref facade must not change downstream runtime semantics.
- **kind:** functional
- **status:** active

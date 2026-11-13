---
modules:
  - Jido.Instance.Options
  - Jido.Instance.NamespaceRegistry
  - Jido.Instance.RuntimeStore
  - Jido.Agent.Address
---

## Purpose

Protect Jido instance configuration, supervision identity, namespaces, Agent
lifecycle selection, and stable Agent Address routing. The public `Jido` module
owns runtime operations. `use Jido` only declares instance configuration and a
supervision child. AgentServer Turn behavior, persistence record meaning, and
downstream operation results stay with their owning components.

## Obligations

### jido.instance.I1 — Instance definition and validation

- **scope:** `use Jido`, generated instance `config/1`, `Jido.child_spec/1`, `Jido.start_link/1`
- **must:** Accept only unique `otp_app`, `namespace`, and `persistence` declaration options and require `otp_app`. Merge application configuration with runtime overrides, keep the generated module as the instance name, and validate the complete option set before any child starts. Reject non-keyword input, duplicate or unknown keys, missing or invalid names, invalid OTP applications, namespaces, debug levels, Task limits, AgentServer defaults, and persistence sources with a structured instance configuration error.
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

- **scope:** `Jido.start_link/1`, `Jido.Instance.NamespaceRegistry.namespace/1`
- **must:** Bind an optional nonempty namespace to at most one live local instance. Keep the exact binding while that instance is live, release an unbound claim after failed startup, remove the binding after owner loss, and restore live bindings after the namespace registry worker restarts.
- **why:** A stable Address namespace must identify one current local instance without becoming stuck after failure.
- **kind:** functional
- **status:** active

### jido.instance.I4 — Fixed instance runtime defaults

- **scope:** generated instance `config/1`, `Jido.Instance.RuntimeStore.instance_persistence/1`, `Jido.Instance.RuntimeStore.instance_agent_server_options/1`
- **must:** Apply runtime options after application and declared defaults. Store the validated persistence source and AgentServer defaults for the live instance. Keep those selected values fixed for that lifetime and available across RuntimeStore worker replacement.
- **why:** Consumers need one stable set of instance defaults.
- **kind:** functional
- **status:** active

### jido.instance.I5 — Agent lifecycle selection

- **scope:** `Jido.start_agent/3`, `Jido.stop_agent/3`, `Jido.whereis_agent/3`, `Jido.list_agents/2`, `Jido.agent_count/2`
- **must:** Require an explicit selected instance for every Agent lifecycle function and route through its exact partition. Isolate equal Agent IDs across instances and partitions. List and count only the selected partition. Reject a PID operation whose explicit partition does not match its registration. A generated instance module must not copy these runtime functions.
- **why:** Instance and partition selection must not target another activation.
- **kind:** functional
- **status:** active

### jido.instance.I6 — Stable Address construction

- **scope:** `Jido.agent_address/3`, `Jido.create_agent/4`, `Jido.activate_agent/3`
- **must:** Build an Address only from a live stable namespace, exact Agent ID, and optional partition. Keep process and storage data out of the Address. Reject malformed Addresses, duplicate or unknown options, namespace mismatch, and operation identity conflicts before writing or starting work. Preserve the same Address identity when its namespace later binds to another local instance.
- **why:** Stable identity must not depend on one process or local instance name.
- **kind:** functional
- **status:** active

### jido.instance.I7 — Address resolution

- **scope:** `Jido.resolve_agent/2`
- **must:** Resolve the exact namespace, partition, and Agent ID through the selected instance Registry. Return the ready AgentServer PID, `not_found` when no matching worker is registered, `recovering` while the matching worker is not ready, and `unavailable` when the Registry or a resolved worker is lost. Resolve each operation again after worker replacement and do not replay work.
- **why:** A stable Address must not retain or reuse a stale PID.
- **kind:** functional
- **status:** active

### jido.instance.I8 — Address operation routing

- **scope:** `Jido.call/4`, `Jido.cast/3`, `Jido.submit/4`, committed reads, and controls
- **must:** Route each supported Address function to the currently resolved AgentServer and preserve its public result and caller-wait contract. Return an AgentServer pending value from submit. Keep await and abandon with `Jido.AgentServer`. Return an explicit error for a missing target. Keep caller timeout separate from execution cancellation.
- **why:** The Address API must not change downstream runtime semantics.
- **kind:** functional
- **status:** active

### jido.instance.I9 — Durable Agent creation and activation

- **scope:** `Jido.create_agent/4`, `Jido.activate_agent/4`
- **must:** Require Instance persistence for durable creation. Create revision zero synchronously and return the exact Agent Address only after that write succeeds. Do not start an activation during creation. Return the current local activation when one exists. Otherwise activation must strictly restore one active durable record. It must not create a missing record or replace a tombstone or invalid record.
- **why:** Logical Agent creation must be durable before activation, and activation must not create a new Agent lifetime by accident.
- **kind:** ordering
- **status:** active

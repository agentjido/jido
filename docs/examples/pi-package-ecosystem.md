> Donor history and research. Counts and result claims below describe an earlier
> source snapshot. Use [the core execution record](../migration/10-execution-record.md) for the migration result.

# Pi package and extension research

Access date: **2026-09-03**.

Pi is a coding Agent CLI and an embeddable Agent SDK. Its package ecosystem is
still useful for Jido because it shows what users add after the basic Agent loop
works.

The official [Pi Package Catalog](https://pi.dev/packages) listed 5,489 packages
when this review ran. Pi packages can contain extensions, skills, prompt
templates, and themes. Pi can install packages from npm, Git, or a local path.
It can load them at user scope or project scope.

Pi extensions are trusted TypeScript modules. They can:

- register tools, commands, input handlers, flags, shortcuts, and model
  providers;
- inspect or change model context and tool results;
- allow, ask about, or block a tool call;
- observe session, Agent, model, message, and tool events;
- keep state in the session log and rebuild it after reload;
- add terminal UI, status, and interactive approval controls;
- start session resources and close them during session shutdown.

See the official [extension documentation](https://github.com/earendil-works/pi/blob/main/packages/coding-agent/docs/extensions.md),
[package documentation](https://github.com/earendil-works/pi/blob/main/packages/coding-agent/docs/packages.md),
and [extension examples](https://github.com/earendil-works/pi/tree/main/packages/coding-agent/examples/extensions).

## What applies to Jido

Pi is a harness around an interactive session. Jido is an Agent runtime. The
same extension API must not move across unchanged.

| Pi extension concern | Jido pressure-test boundary |
| --- | --- |
| Custom model tool | A typed `Jido.Action` or a tool catalog used by a Flow |
| Tool interception | An explicit permission decision before an effect |
| Session event listener | Read-only observation of Signal, Turn, Flow, and runtime outcomes |
| Session state entry | Agent state, Thread entries, or Plugin-owned runtime state |
| Background process | A supervised OTP child owned by an explicit runtime capability |
| Command or web input | An input adapter that sends a Signal |
| Session UI | A separate consumer of state, Signals, and observation events |
| Package manifest | Application configuration that selects explicit capabilities |
| Prompt or compaction hook | A visible Action or Flow selected by a Signal |

The useful split is:

1. Actions and Flows own program composition and can perform effects.
2. Directives request runtime state changes and supervised runtime work.
3. Input adapters convert external input into Signals.
4. Observers receive events but do not change a Turn.
5. Runtime capabilities own OTP processes and their lifecycle.

This split keeps Pi-like power without putting tools, middleware, state,
observation, user interface, and supervision into one Plugin contract.

## Packages sampled

The research used these package pages as concrete examples:

- [pi-mcp-adapter](https://pi.dev/packages/pi-mcp-adapter): lazy tool discovery
  and MCP provider startup.
- [pi-subagents](https://pi.dev/packages/pi-subagents): foreground and
  background child Agents, saved workflows, and fleet observation.
- [pi-background-tasks](https://pi.dev/packages/pi-background-tasks): durable
  jobs, completion delivery, cancellation, and bounded output.
- [@juicesharp/rpiv-todo](https://pi.dev/packages/@juicesharp/rpiv-todo):
  session-replayed state with visible task dependencies.
- [pi-memory](https://pi.dev/packages/pi-memory): durable project memory and
  semantic retrieval.
- [@gotgenes/pi-permission-system](https://pi.dev/packages/@gotgenes/pi-permission-system):
  deterministic allow, ask, and deny decisions for tools and paths.
- [@raindrop-ai/pi-agent](https://pi.dev/packages/@raindrop-ai/pi-agent) and
  [@braintrust/pi-extension](https://pi.dev/packages/@braintrust/pi-extension):
  automatic Agent, model, and tool tracing.
- [@quintinshaw/pi-dynamic-workflows](https://pi.dev/packages/@quintinshaw/pi-dynamic-workflows):
  code-first fan-out, model routing, budgets, resume, and verification.
- [pi-web-ui](https://pi.dev/packages/pi-web-ui): an alternate host that runs
  the Agent SDK and streams its state to a browser.

## New Jido pressure tests

- [Extension Package Lifecycle](archive/runtime/04_21_extension_package_lifecycle.md)
- [Tool Permission Gate](archive/runtime/04_26_tool_permission_gate.md)
- [Dynamic Tool Catalog](archive/runtime/04_06_dynamic_tool_catalog.md)
- [Session-Replayed Task Board](archive/runtime/04_11_session_replayed_task_board.md)
- [Background Job Supervisor](archive/runtime/04_15_background_job_supervisor.md)
- [Automatic Trace Subscriber](archive/runtime/04_14_automatic_trace_subscriber.md)
- [Session Compaction Policy](archive/runtime/04_10_session_compaction_policy.md)
- [Scripted Workflow Fan-Out](archive/multi_agent/05_24_scripted_workflow_fanout.md)

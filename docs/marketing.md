# Jido V3 Marketing: Friday Facts Series

A blog series in the style of Factorio's "Friday Facts". Each post shows a real
problem, the design that fixed it, and something you can see or run. Every
post covers one major V2 → V3 change and why it works best on the BEAM.

Proposed order:

0. (Optional) Why V3? Or fold it into #1.
1. One Signal, One Decision
2. Commit, Then Act
3. Your Agent Is Just Data
4. Plugins That Own Their State
5. Agents All the Way Down
6. Survive the Restart
7. Production Is a Feature
8. (Optional closer) V2 → V3 migration

## 1. One Signal, One Decision: the new core loop

- **V2 → V3:** V2 had pluggable strategies (FSM, custom strategies) and
  several ways for an Agent to decide what to do. In V3, a Signal matches the
  first route, the route runs one Action or Flow, and that returns the
  complete next state plus Directives.
- **BEAM angle:** each Agent is one process with its own mailbox, so Turns run
  one at a time without locks. Concurrency comes from running many Agents,
  not from sharing state inside one.
- **Demo:** the "Life of a Signal" diagram, animated one stage at a time:
  admission → preparation → execution → validation → save → commit → effects.
- **Hook:** "We deleted the strategy layer. Here's why that was the most
  important change in V3."

## 2. Commit, Then Act: state before side effects

- **V2 → V3:** in V3, effects are Directives. They run only after the new
  state is validated and committed (and saved, if persistence is on). A
  failed Turn sends no emits and starts no processes.
- **BEAM angle:** effects run in linked tasks under supervision, so a crashing
  effect can't corrupt state that's already committed.
- **Demo:** an Action that fails validation. The counter stays at revision 3,
  and the Emit never goes out. Next to it, a successful Turn where the reply
  arrives before the Directive runs.
- **Hook:** "Most agent frameworks call the API and then hope the state update
  works. We flipped the order."

## 3. Your Agent Is Just Data: pure `cmd/3` vs the live Server

- **V2 → V3:** the same Agent definition runs purely with `cmd/3` (no process,
  Directives come back as data) or live under `Jido.AgentServer`.
- **BEAM angle:** immutable data plus OTP. You test decisions as plain values,
  then run the identical code as a supervised `:gen_statem`.
- **Demo:** replay 10,000 Signals through `cmd/3` in a test in milliseconds,
  then start the same instance live with `start_agent(agent)`.
- **Hook:** "Unit-testing an AI agent shouldn't need a mock LLM, a process, or
  a prayer."

## 4. Plugins That Own Their State

- **V2 → V3:** V3 Plugins each own one field of state. They hook into the
  Turn at fixed points: `prepare/2`, `admit/3`, `reduce/2`, `after_commit/3`.
  Actions can read a Plugin's field but can't write it.
- **BEAM angle:** a Plugin can bring supervised resources that start and stop
  with the Agent's activation tree (`one_for_all`).
- **Demo:** the Ledger Plugin from Stateful Plugins. The `tamper` route tries
  to overwrite the ledger and is rejected, and the live Server refuses
  "mallory" at admission.
- **Hook:** "Middleware is easy. Middleware nobody else can break is the hard
  part."

## 5. Agents All the Way Down: composition and topology

- **V2 → V3:** V2's child Agents become declared topologies: nested Agents,
  connections between their outputs, and composition you can change while the
  system is running.
- **BEAM angle:** supervision trees are the composition model. A child crash
  stays inside its own supervisor, and connections route Signals between
  Agents with no shared memory.
- **Demo:** rewire a running pipeline by adding a connection mid-stream, then
  kill a child process and watch it come back.
- **Hook:** "Erlang has done multi-agent systems since 1986. We just stopped
  hiding it."

## 6. Survive the Restart: durability built in

- **V2 → V3:** V3 adds revisioned commits, hibernate and thaw, durable Turns
  and Flows, checkpoints, and seven persistence adapters (ETS, File, Mnesia,
  Ecto, Redis, S3, Bedrock).
- **BEAM angle:** an Agent can be "let it crash" and still durable at the same
  time. A process can hibernate, free its memory, and thaw later on demand.
- **Demo:** a multi-step Flow mid-run, `kill -9` the node, restart, and watch
  it pick up from the last committed revision.
- **Hook:** "A million idle agents should cost you disk, not RAM."
- **Caution:** this only works with `persistence: :inherit` set. Without
  persistence, an activation crash silently resets the Agent to revision 0,
  so the demo must enable it. Make sure the bugs listed under Behavior in the
  QA notes (the `:changed_reference` upgrade path, the `durable_turn` status
  race) don't show up in it.

## 7. Production Is a Feature: admission, deadlines, observability

- **V2 → V3:** the Agent Server is now a `:gen_statem` with admission
  deadlines, `quiesce/2`, `submit`/`await`/`abandon`, structured Turn
  summaries in `status/2` and `history/1`, and standard telemetry metrics.
- **BEAM angle:** these are OTP-native backpressure and introspection tools,
  so you can look inside a live Agent from a remote shell.
- **Demo:** flood one Agent and show the admission deadlines rejecting
  cleanly. Then connect to a running node and read `status/2` live.
- **Hook:** "What does your agent framework do on its worst day?"
- **Caution:** the "Runnable failed" log leak and the `debug/1` gap are both
  in the QA notes. Fix them before this post, or it invites an awkward reply.

## Scheduling

Topics 1–3 can go out today. The demos for 4–7 depend on library fixes from
the QA notes (`.claude/research/2026-10-19-guides-qa-notes.md`): Plugin config
in Livebook, persistence defaults, and log leaks. Schedule those posts after
the fixes land.

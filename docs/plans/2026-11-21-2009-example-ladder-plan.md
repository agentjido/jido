---
title: Refine the Jido example ladder
type: implementation-plan
date: 2026-11-21
last_reviewed: 2026-11-21
artifact_contract: kata-plan/v1
artifact_readiness: implementation-ready
domain: software
execution: code
product_contract_source: direct-request
---

# Refine the Jido example ladder

## Goal Capsule

Update the approved ladder in Jido Core. Keep the six expense lessons in Learn
and make all supported examples accessible in Browse. Use local-write
authority in a clean checkout of main at `322bbf0f`. The implementation owner
checks the final examples and Explorer. Stop when the acceptance checks pass
or the evidence identifies an unresolved blocker.

## Product Contract

### Summary

Make the example ladder easier to follow and use it to test distinct Core
contracts.

### Problem frame

Two examples duplicate published lessons. Recent Flow, Statechart, browser,
and Thread changes need direct coverage in the ladder.

### Actors

A new Jido user follows Learn. A developer searches Browse and runs an
example. A maintainer runs the offline suite.

### Requirements and acceptance examples

| Requirement | User result | Acceptance example |
| --- | --- | --- |
| R1 | Find the next task after Learn and see all Browse chapters in one sidebar. | The last lesson offers batch, recovery, and Support Desk links. Crash recovery and Timer lessons are listed together. |
| R2 | Read one batch lesson and one Address lesson. | Ordered Batch keeps its error checks and proves the worker limit. Logical Identity rejects malformed Addresses and preserves identity after replacement. |
| R3 | Run a bounded repair with a child Flow. | The next pass uses the previous result. Exhaustion leaves the prior Agent state in place. |
| R4 | Try a browser tool offline. | The same Agent returns a cited fixture answer when permitted and reports a denial before transport when blocked. |
| R5 | See a Statechart cancel a deadline. | Expiration sends the expiry event. Confirmation cancels that event while the chart remains active. |
| R6 | Diagnose a malformed archived Thread. | Rollover reports a decode error before it can return a replacement Session. |
| R7 | Read the Explorer in the system appearance. | The page and syntax highlighting switch with the system preference. Dark mode uses navy surfaces and blue accents. |

### Key flows

Learn ends with three task links. Browse opens lessons, shows source, runs a
selected test, or runs the local browser-tool demo.

### Success criteria

The catalog retains 206 lessons. Each changed contract has its own offline
proof. The demo gives a cited answer for one fixture and a refusal for the
other.

### Scope boundaries

This effort changes examples, Explorer navigation, and the browser transport
boundary. A combined Statechart and Behavior Tree is deferred until there
is a public composition pattern. Git delivery is outside the current
request.

### Key decisions

Keep the six expense lessons and the two application showcases, Support
Desk and Phoenix Chat. Combine batch work and Address identity in their
respective chapters.

### Rejected alternatives

A new support application or a separate crash-recovery track would
duplicate existing lessons. Extend the existing sample when it can own the
new proof. The Explorer uses the system appearance preference directly.

### Dependencies

The demo uses the existing ReAct and browser Action path. The Explorer
uses the existing opt-in Playground dependencies.

### Outstanding questions

None that block this scope.

### Sources

The accepted ladder review in this chat and the
[repository example instructions](../../examples/AGENTS.md).

## Planning Contract

### Product Contract preservation

The user's approved ladder defines the catalog requirements. The follow-up adds R7.

### Current system

The [Explorer](../../examples/playground/explorer_live.ex) derives its catalog
from numbered folders. Browse currently shows one chapter at a time without
search text. The released catalog has two numbered entries for batch work
and two for stable Address identity.

### Target system

Group the full catalog by chapter and keep the active lesson visible. Retire
the duplicate slots and route their old Explorer URLs to the combined
lessons.

### Key technical decisions

- KTD1 (R1–R2). Use the existing folder-derived catalog. Keep two old lesson
  IDs as aliases and update all published links inside the repository.
- KTD2 (R2–R3, R5–R6). Put deterministic probes beside their owning tests.
  Keep lesson code on public Flow, Statechart, AgentServer, and Session paths.
- KTD3 (R4). The [browser](../../lib/jido/ai/browser.ex) owns URL policy and
  calls a fixed network backend today. Let the host configure a page transport
  after the policy check so the demo can use a fixture on the real tool path.
  Keep the built-in network transport as the default. Restore configuration
  after integration tests.

### System boundaries and change surface

- Numbered folders own lesson inventory and colocation of code and tests.
- The Explorer owns search, route aliases, system theme styling, and local demo input.
- The browser tool owns policy, public-IP checks, redirects, and size bounds.
  The configured transport owns resolution and page I/O.

### Implementation units

1. U1 (R2–R3, R6). Combine the two pairs, keep unique proof, extend the
   iteration and rollover cases, and update chapter links.
2. U2 (R5). Add the chart, tests, and chapter entry. Observe deadline and
   confirm paths on live Agents.
3. U3 (R4). Add the host transport seam, fixture, Agent, tests, and CLI runner.
   Check the real tool path with and without host permission.
4. U4 (R1, R4, R7; after U1–U3). Update the task index and Explorer. Add the
   browser-tool form and inline result. Apply the system theme to the interface and code previews.

### Work graph

U1, U2, and U3 can start independently. U4 integrates their lessons into
Browse and adds the demo and Learn links.

### Verification contract

Run all commands from the checkout root.

| Gate | Requirements | Evidence |
| --- | --- | --- |
| Focused | R2–R6 | Run `mix test.examples <lesson-path> --warnings-as-errors` on each touched lesson and run the release-note CLI demo. |
| Integration | R1–R6 | Run the full example suite and the offline CI alias. Check chapter links, unique lesson IDs, and the inventory count. |
| Browser | R1, R4, R7 | Start the opt-in Playground. Check navigation, both demo choices, inline verbose test output, and system light and dark preferences. |
| Format | All | Run `mix format --check-formatted` and `git diff --check`. |

### Rollout and recovery

The result is a local diff. The new browser transport is opt-in. The fixture
receives a policy-approved URI and uses no network. The Explorer continues
to load only with the Playground flag.

### Risks and assumptions

The Statechart has no public fake clock. Observe actual chart events and use
a bounded deadline for the test. Scope the browser fixture to the local
Explorer process and the serialized integration test.

### Open planning decisions

None.

### Definition of done

All seven requirements have direct evidence. The catalog contains 206
numbered lessons, each with source and a colocated test. Retired lessons
have no broken repository links. The current dirty checkout is outside this
change set.

### Planning sources

- [Explorer](../../examples/playground/explorer_live.ex)
- [Browser policy and fetch](../../lib/jido/ai/browser.ex)
- [Statechart guide](../../guides/built-in-plugins/statecharts.md)
- [Example table of contents](../../examples/table_of_contents.md)

## Adapter Results

Markdown is the canonical plan.

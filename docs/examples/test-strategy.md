> Donor history and research. Counts and result claims below describe an earlier
> source snapshot. Use [the core execution record](../migration/10-execution-record.md) for the migration result.

# Example test strategy

## SDK integration tests

An SDK integration test combines real public Jido components and proves a
specific boundary between them. A live external service is not required.
Use real Agent construction, Signal routing, Action or Flow execution, Plugin
composition, Server commit, and Directive dispatch for the boundary under test.
Test adapters may replace external services; they must not replace the SDK
components whose integration the test claims to prove.

[Basic](../../test/examples/01_basic/README.md) is the smallest required set: five
fixtures and fifteen tests for execution agreement, validation, ownership,
atomic commit, effect order, and Turn control. Run it with:

```shell
mix test --include integration test/examples/01_basic
```

Basic has both `:integration` and `:example` tags. Its failures stay enabled.
A new Basic case must name a distinct SDK obligation and an observable result.
A different business rule alone does not justify another integration test.

Domain unit tests and teaching examples can test calculations, list operations,
or transition tables without repeating the Server success path.

[Workflow](../../test/examples/02_workflow/README.md) adds nine fixtures and 33
integration tests for graph dependencies, context, effects, Choice, concurrency,
Map/Reduce, Iterate, Subflow, continuation, and approval. Run it with:

```shell
mix test --include integration test/examples/02_workflow
```

The same tagging and enabled-failure rules apply. Use barriers to prove actual
execution order, result order, worker cleanup, and snapshot visibility.

## Deterministic test controls

Use this class by default. A local test can still test an Action or Flow that
performs external effects. Replace the live client with an injected adapter and
record calls in memory.

Use these controls:

- fixed Signal IDs, correlation IDs, and trace data;
- a fake clock for time and schedule calculations;
- fake model replies for tool calls, structured outputs, and retries;
- fixture documents and an in-memory retriever;
- in-memory HTTP, database, file, email, and message adapters;
- deterministic task barriers for concurrency tests;
- `JidoTest.Eventually` for runtime assertions, with no fixed sleeps.

Assert the complete Agent state after one commit. Then assert runtime work and
follow-up Signals. If an Action or Flow does external work before commit, assert
the idempotency key and the response that enters the one committed state.

## Live service integration tests

Keep live tests separate from the default suite. Tag them by service and make
credentials optional. Use a live service integration test for:

- a real LLM or embedding model;
- a remote vector database or SQL server;
- a live browser, Slack, email, spreadsheet, or ticket system;
- MCP, A2A, or another network protocol;
- realtime audio, image, or video services;
- a multi-node distributed cluster;
- a durable workflow engine outside Jido.

The older catalog label `true integration` means a live service requirement.
It does not exclude local SDK integration tests from being integration tests.

Every live example should also have a local contract test. The local test must
cover response parsing, errors, timeouts, retries, and duplicate delivery.

## One-commit checks

For state-changing integration scenarios, verify the relevant boundaries in this order:

1. One Signal enters the Agent mailbox.
2. Routing selects one Action or one Flow.
3. The executable can call its injected external adapters.
4. It returns one complete candidate state and zero or more Directives.
5. The Agent Server commits the state one time.
6. The runtime applies Directives in order.
7. Later results enter as new Signals and start new finite turns.

Do not split domain state changes across Directives. Do not add an effect-free
Turn rule. Record a safe retry key for each irreversible external call.

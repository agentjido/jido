# Factory examples

These application examples build from one live conversation to Agent-owned
factories and a large Flow-driven proposal system. The default tests use local
provider responses and need no key.

## Learning order

1. [Live Conversation](06_01_live_conversation/README.md) — keep model history in Agent state and provider resources in context.
2. [Three-Agent System](06_02_three_agent_system/README.md) — own a conversation, a queue manager, and temporary workers.
3. [Department Factory](06_03_department_factory/README.md) — run an explicit dependency plan through persistent department Agents.
4. [Flow Factory](06_04_flow_factory/README.md) — coordinate worker Agents with parallel, conditional, and bounded repair Flow structures.

## Run the section

```sh
mix test test/examples/06_factory --include example --seed 0
```

Expected result: all application behavior passes against local deterministic
provider responses.

## Optional live run

Set `FACTORY_MODEL` and the selected provider key in the repository `.env` or
shell. Then run:

```sh
mix run examples/06_factory/chat.exs conversation
```

The shell environment has priority over `.env`. Never put a key in source,
Agent state, Signals, Directives, fixtures, or test output.

## Shared support

The [support folder](support/) contains the bounded model loop, asynchronous
Plugin, shared command protocol, inspection Action, tools, and safe error
formatting used by two or more factory examples.

## Limits

These examples produce demonstration or proposal artifacts. They do not change
a repository, run an external deployment, or persist an active factory.
